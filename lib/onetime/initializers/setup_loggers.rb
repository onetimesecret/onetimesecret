# lib/onetime/initializers/setup_loggers.rb
#
# frozen_string_literal: true

require 'yaml'
require 'semantic_logger'
require_relative '../utils/config_resolver'

module Onetime
  module Initializers
    # Configures SemanticLogger with strategic categories for debugging.
    #
    # Categories: App, Auth, Billing, Boot, Bunny, Familia, HTTP, Jobs,
    # Otto, Rhales, Secret, Sequel, Session.
    #
    # Configuration loaded from etc/logging.yaml with environment variable
    # overrides. Logger instances are cached because SemanticLogger[]
    # creates new instances on each call.
    #
    # Environment variables:
    #   LOG_LEVEL        - Global default level (trace/debug/info/warn/error/fatal)
    #   ONETIME_DEBUG    - Sets global default to debug when truthy
    #   BACKTRACE_LEVEL  - Level at which backtraces are included (default: error)
    #   BACKTRACE_LINES  - Max exception backtrace lines (default: 3 in prod, unlimited in dev)
    #   DEBUG_*          - Per-category debug flags (e.g., DEBUG_AUTH=1)
    #   DEBUG_LOGGERS    - Fine-grained control (e.g., "Auth:debug,Secret:trace")
    #
    # Runtime state set:
    #   Onetime::Runtime.infrastructure.cached_loggers
    #
    class SetupLoggers < Onetime::Boot::Initializer
      @provides           = [:logging].freeze
      @phase              = :fork_sensitive
      @logger_definitions = {
        'App' => 'DEBUG_APP',
        'Auth' => 'DEBUG_AUTH',
        'Billing' => 'DEBUG_BILLING',
        'Boot' => 'DEBUG_BOOT',
        'Bunny' => 'DEBUG_BUNNY',
        'Familia' => 'DEBUG_FAMILIA',
        'HTTP' => 'DEBUG_HTTP',
        'Otto' => 'DEBUG_OTTO',
        'Rhales' => 'DEBUG_RHALES',
        'Scheduler' => 'DEBUG_SCHEDULER',
        'Secret' => 'DEBUG_SECRET',
        'Sequel' => 'DEBUG_SEQUEL',
        'Session' => 'DEBUG_SESSION',
        'Workers' => 'DEBUG_WORKERS',
      }.freeze

      class << self
        attr_reader :logger_definitions
      end

      def execute(_context)
        @debug_boot          = OT::Utils.yes?(ENV.fetch('DEBUG_BOOT', nil))
        config               = load_logging_config
        Onetime.logging_conf = config

        configure_default_level(config)
        configure_appender(config)

        cached_loggers = create_cached_loggers(config)
        apply_env_overrides(cached_loggers)
        configure_external_loggers(cached_loggers)

        log_effective_configuration(cached_loggers) if Onetime.debug?
        Onetime::Runtime.update_infrastructure(cached_loggers: cached_loggers)
      end

      # Cleanup SemanticLogger before fork.
      # Called by InitializerRegistry.cleanup_before_fork from Puma's before_fork hook.
      #
      # Flushes async appender to prevent lost log messages. The async appender
      # queues messages in a background thread that won't survive fork.
      #
      # @return [void]
      def cleanup
        SemanticLogger.flush if defined?(SemanticLogger)
      rescue StandardError => ex
        warn "[SetupLoggers] Error during cleanup: #{ex.message}"
      end

      # Reconnect SemanticLogger after fork.
      # Called by InitializerRegistry.reconnect_after_fork from Puma's before_worker_boot hook.
      #
      # Re-opens appenders to create fresh async processing threads, replacing
      # zombie thread references inherited from the master process.
      #
      # @return [void]
      def reconnect
        SemanticLogger.reopen if defined?(SemanticLogger)
      rescue StandardError => ex
        warn "[SetupLoggers] Error during reconnect: #{ex.message}"
      end

      private

      def load_logging_config
        path = Onetime::Utils::ConfigResolver.resolve('logging')
        return {} unless path

        YAML.load(ERB.new(File.read(path)).result)
      end

      # Precedence: LOG_LEVEL env > ONETIME_DEBUG > config file > :info default
      def configure_default_level(config)
        SemanticLogger.default_level = ENV['LOG_LEVEL']&.to_sym ||
                                       config['default_level']&.to_sym ||
                                       :info

        SemanticLogger.default_level   = :debug if Onetime.debug?
        SemanticLogger.backtrace_level = ENV['BACKTRACE_LEVEL']&.to_sym || :error
      end

      def configure_appender(config)
        # Skip if console appender already exists (prevents duplicates during test reruns)
        return if SemanticLogger.appenders.any?(SemanticLogger::Appender::IO)

        formatter = build_formatter(config)

        # Async appender handles logging in background thread. The reopen hook in
        # reconnect method ensures fresh threads after fork, preventing zombie references.
        SemanticLogger.add_appender(
          io: $stdout,
          formatter: formatter,
        )
      end

      # Build formatter with environment-aware exception handling
      #
      # In production, exception backtraces are truncated to reduce log noise.
      # Full backtraces go to error tracking (Sentry), not application logs.
      #
      # Environment variables:
      #   BACKTRACE_LINES - Max backtrace lines to include (default: 3 in prod, unlimited in dev)
      #
      def build_formatter(config)
        base_formatter = config['formatter']&.to_sym || :color
        max_lines      = backtrace_limit

        # In development/test, use standard formatter with full backtraces
        return base_formatter unless max_lines

        # In production, wrap formatter to truncate exception backtraces
        proc do |log, logger|
          truncate_exception_backtrace(log, max_lines)
          SemanticLogger::Formatters.factory(base_formatter).call(log, logger)
        end
      end

      # Determine backtrace line limit based on environment
      #
      # @return [Integer, nil] Max lines, or nil for unlimited
      def backtrace_limit
        # Explicit override takes precedence
        return ENV['BACKTRACE_LINES'].to_i if ENV['BACKTRACE_LINES']

        # Production defaults to 3 lines, others unlimited
        case Onetime.mode
        when 'production' then 3
        end
      end

      # Truncate exception backtrace in-place
      def truncate_exception_backtrace(log, max_lines)
        return unless log.exception&.backtrace

        original_size = log.exception.backtrace.size
        return if original_size <= max_lines

        log.exception.backtrace.slice!(max_lines..-1)
        log.exception.backtrace << "... (#{original_size - max_lines} more lines)"
      end

      # Create and cache logger instances with levels from config
      def create_cached_loggers(config)
        self.class.logger_definitions.each_with_object({}) do |(name, _), cache|
          level        = config.dig('loggers', name)&.to_sym || SemanticLogger.default_level
          warn " initialize #{name}=#{level}" if @debug_boot
          logger       = SemanticLogger[name]
          logger.level = level
          cache[name]  = logger
        end
      end

      # Apply DEBUG_* flags and DEBUG_LOGGERS overrides
      def apply_env_overrides(cached_loggers)
        # DEBUG_* flags set logger to debug level
        self.class.logger_definitions.each do |name, env_var|
          next unless OT::Utils.yes?(ENV[env_var])

          cached_loggers[name].level = :debug
        end

        # DEBUG_LOGGERS=Auth:debug,Secret:trace for fine-grained control
        ENV['DEBUG_LOGGERS']&.split(',')&.each do |spec|
          name, level = spec.split(/[:=]/, 2).map(&:strip)
          next unless name && level

          (cached_loggers[name] ||= SemanticLogger[name]).level = level.to_sym
        end
      end

      # Wire up external libraries to use our cached loggers
      def configure_external_loggers(cached_loggers)
        Familia.logger = cached_loggers['Familia']
        Otto.logger    = cached_loggers['Otto']
        Otto.debug     = Onetime.debug?

        configure_familia_hooks
      end

      # Register Familia hooks for Redis command and lifecycle logging.
      # Uses sampling in production to reduce volume.
      def configure_familia_hooks
        return unless defined?(Familia::DatabaseLogger)

        Familia::DatabaseLogger.sample_rate = case Onetime.conf[:environment]
        when 'production' then ENV['FAMILIA_SAMPLE_RATE']&.to_f || 0.01
        when 'development' then ENV['FAMILIA_SAMPLE_RATE']&.to_f || 1.0
        end

        if Familia.respond_to?(:on_command)
          Familia.on_command do |cmd, duration, context|
            Familia.logger.debug 'Redis command',
              command: cmd, duration: duration, context: context
          end
        end

        return unless Familia.respond_to?(:on_lifecycle)

        Familia.on_lifecycle do |event, instance, context|
          Familia.logger.debug 'Familia lifecycle',
            event: event,
            class: instance.class.name,
            identifier: instance.respond_to?(:identifier) ? instance.identifier : nil,
            context: context
        end
      end

      def log_effective_configuration(cached_loggers)
        default   = SemanticLogger.default_level
        overrides = cached_loggers.filter_map do |name, logger|
          "#{name}=#{logger.level}" if logger.level != default
        end
        warn " default=#{default}, overrides: #{overrides.any? ? overrides.join(', ') : '(none)'}"
      end
    end
  end
end
