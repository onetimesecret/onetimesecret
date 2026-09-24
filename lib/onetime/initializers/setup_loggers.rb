# lib/onetime/initializers/setup_loggers.rb
#
# frozen_string_literal: true

require 'yaml'
require 'date' # ensure Date/Time constants resolve for permitted_classes
require 'semantic_logger'
require_relative '../utils/config_resolver'
require_relative '../utils/enumerables'

module Onetime
  module Initializers
    # Configures SemanticLogger with strategic categories for debugging.
    #
    # Categories: App, Auth, Billing, Boot, Bunny, Ents, Familia, HTTP,
    # Jobs, Org, Otto, Rhales, Secret, Sequel, Session.
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
      # SemanticLogger category the operator audit sink emits on (#4334).
      #
      # A literal, not Onetime::ColonelAuditEvent::SINK_LOGGER_NAME, because
      # this initializer runs in the :fork_sensitive boot phase — before the
      # models are loaded — and referencing the constant there would raise
      # NameError into the appender's rescue and silently disable the operator's
      # configured audit destination. The two MUST agree; a spec pins that
      # (spec/unit/onetime/models/colonel_audit_event_spec.rb).
      AUDIT_SINK_LOGGER_NAME = 'ColonelAudit'

      # Exact-name filter for the audit syslog appender. SemanticLogger matches
      # `filter` against the logger NAME, and a loose pattern would quietly
      # start copying unrelated categories into the operator's audit
      # destination.
      AUDIT_SINK_FILTER = /\A#{Regexp.escape(AUDIT_SINK_LOGGER_NAME)}\z/

      @provides           = [:logging].freeze
      @phase              = :fork_sensitive
      @logger_definitions = {
        'App' => 'DEBUG_APP',
        'Auth' => 'DEBUG_AUTH',
        'Billing' => 'DEBUG_BILLING',
        'Boot' => 'DEBUG_BOOT',
        'Bunny' => 'DEBUG_BUNNY',
        'Ents' => 'DEBUG_ENTS',
        'Familia' => 'DEBUG_FAMILIA',
        'HTTP' => 'DEBUG_HTTP',
        'Jobs' => 'DEBUG_JOBS',
        'Org' => 'DEBUG_ORG',
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

        SemanticLogger.application = 'onetimesecret'

        configure_default_level(config)
        configure_appender(config)
        configure_audit_syslog_appender(config)

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
      # Called by InitializerRegistry.reconnect_after_fork from fork hooks (Puma, Sneakers).
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
        defaults_file = Onetime::Utils::ConfigResolver.defaults_path('logging')
        override_file = Onetime::Utils::ConfigResolver.resolve('logging')

        # safe_load prevents a malicious logger config from instantiating
        # arbitrary Ruby objects; Symbol is permitted because log levels and
        # category keys are symbols. Date and Time are permitted so an
        # unquoted date/time in a logging config loads as a Date/Time instance
        # rather than raising Psych::DisallowedClass and breaking boot (per
        # issue #3498). aliases: true keeps YAML anchors working for shared
        # formatter/appender settings.
        base_config = if defaults_file
          YAML.safe_load(ERB.new(File.read(defaults_file)).result, permitted_classes: [Symbol, Date, Time], aliases: true) || {}
        else
          {}
        end

        env_config = if override_file && override_file != defaults_file
          YAML.safe_load(ERB.new(File.read(override_file)).result, permitted_classes: [Symbol, Date, Time], aliases: true) || {}
        else
          {}
        end

        return base_config if env_config.empty?
        return env_config if base_config.empty?

        Onetime::Utils::Enumerables.deep_merge(base_config, env_config, preserve_nils: false)
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
          io: log_device,
          formatter: formatter,
        )
      end

      # OPTIONAL syslog appender for the operator audit sink (#4334).
      #
      # Onetime::ColonelAuditEvent emits every audit event as a structured log
      # line on the dedicated `ColonelAudit` category BEFORE writing it to
      # Valkey — that stream, not the capped sorted set, is the durability
      # story. By default it rides the console appender above (stdout, which
      # container log collectors already read). Operators who need the audit
      # stream shipped SEPARATELY from application logs — a SIEM, a write-once
      # host, its own retention — enable this.
      #
      # DEFAULT OFF, and no third-party dependency for the default URL:
      # SemanticLogger ships the syslog appender in-gem, and `syslog://` (the
      # local daemon) speaks through Ruby's own `syslog` library — declared in
      # the Gemfile's stdlib section because Ruby 3.4 made it a bundled gem.
      # A `tcp://` / `udp://` URL ships to a REMOTE syslog server and needs the
      # third-party `syslog_protocol` gem, which this repo does not bundle; the
      # rescue below turns that into one warning at boot rather than a failed
      # start.
      #
      # FILTERED to the audit category ({AUDIT_SINK_FILTER}), so enabling it
      # ships the audit stream and nothing else.
      #
      # Idempotent for the same reason configure_appender is: test reruns and
      # re-executed initializers must not stack duplicate appenders. Matched by
      # class NAME because the constant is only defined once add_appender has
      # loaded the appender file.
      def configure_audit_syslog_appender(config)
        settings = config.dig('audit', 'syslog') || {}
        return unless OT::Utils.yes?(settings['enabled'])
        return if SemanticLogger.appenders.any? { |appender| appender.class.name.to_s.end_with?('Appender::Syslog') }

        require 'syslog'

        SemanticLogger.add_appender(
          appender: :syslog,
          url: settings['url'].to_s.empty? ? 'syslog://localhost' : settings['url'].to_s,
          level: (settings['level'] || 'info').to_sym,
          facility: syslog_facility(settings['facility']),
          level_map: syslog_level_map,
          filter: AUDIT_SINK_FILTER,
        )
      rescue StandardError, LoadError => ex
        # Never fail boot over an optional log destination. The sink still
        # reaches stdout via the console appender, so the audit stream is not
        # lost — only its second copy is.
        warn "[SetupLoggers] audit syslog appender not enabled: #{ex.class}: #{ex.message}"
      end

      # Resolve a syslog facility NAME (local0, daemon, authpriv, …) to the
      # ::Syslog integer constant the appender wants. Config carries the name
      # because an operator writes `facility: local0`, not a bitmask.
      #
      # Anything unrecognised falls back to LOG_USER rather than raising: a
      # typo in a logging config must not cost the audit sink its second
      # destination. const_get is bounded to LOG_-prefixed names on ::Syslog,
      # so a config value can never reach an arbitrary constant.
      def syslog_facility(name)
        candidate = "LOG_#{name.to_s.strip.upcase}"
        return ::Syslog::LOG_USER unless candidate.match?(/\ALOG_[A-Z0-9]+\z/) && ::Syslog.const_defined?(candidate)

        ::Syslog.const_get(candidate)
      end

      # SemanticLogger level → syslog severity, supplied EXPLICITLY.
      #
      # Not a nicety: the appender's `level_map:` default value is
      # `SemanticLogger::Formatters::Syslog::LevelMap.new`, and merely
      # evaluating that default autoloads a formatter file whose first line is
      # `require "syslog_protocol"` — so omitting this argument makes even the
      # LOCAL `syslog://` case demand a remote-logging gem we do not bundle.
      # Passing a plain Hash (which the appender indexes with `[]`, same as a
      # LevelMap) keeps the local path dependency-free.
      #
      # The values mirror the gem's documented defaults; syslog severities are
      # fixed by RFC 5424, so there is nothing here that drifts.
      #
      # A method rather than a constant: ::Syslog is only required when the
      # appender is actually being enabled, so a constant would have to resolve
      # those values at class-definition time.
      def syslog_level_map
        {
          trace: ::Syslog::LOG_DEBUG,
          debug: ::Syslog::LOG_INFO,
          info: ::Syslog::LOG_NOTICE,
          warn: ::Syslog::LOG_WARNING,
          error: ::Syslog::LOG_ERR,
          fatal: ::Syslog::LOG_CRIT,
        }.freeze
      end

      # Where console logs go.
      #
      # Server modes log to stdout, which is what container runtimes and log
      # collectors read. A CLI cannot: stdout is its data channel — `--json`
      # output, piped listings, anything a caller parses. Boot diagnostics
      # sharing that stream corrupt it, and the caller has no way to tell a log
      # line from a result. Diagnostics are not the command's output, so in CLI
      # mode they go to stderr.
      #
      # @return [IO]
      def log_device
        OT.mode?(:cli) ? $stderr : $stdout
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
        base_formatter = if OT.mode?(:cli)
                           :color  # Human-readable for CLI
                         else
                           config['formatter']&.to_sym || :color
                         end
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
              command: cmd,
              duration: duration,
              context: context
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
        if Onetime.debug?
          warn " default=#{default}, overrides: #{overrides.any? ? overrides.join(', ') : '(none)'}"
        end
      end
    end
  end
end
