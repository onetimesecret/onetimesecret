# lib/onetime/initializers/semantic_logger.rb

require 'yaml'
require 'semantic_logger'

module Onetime
  module Initializers
    # Configure SemanticLogger with strategic categories for debugging and
    # operational instrumentation. Categories: Auth, Session, HTTP, Familia,
    # Otto, Rhales, Secret, App (default).
    #
    # Configuration loaded from etc/logging.yaml with environment variable
    # overrides for flexible development and production use.
    #
    # IMPORTANT: SemanticLogger[] creates a NEW logger instance each time.
    # We must cache logger instances after setting their levels, otherwise
    # the level settings are lost.
    #
    def configure_logging
      Onetime.ld '[Logging] Initializing SemanticLogger'
      config = load_logging_config

      # Base configuration - set default level first
      SemanticLogger.default_level = config['default_level']&.to_sym || :info

      # Add appender
      SemanticLogger.add_appender(
        io: $stdout,
        formatter: config['formatter']&.to_sym || :color,
      )

      # Environment variable overrides for default_level only
      # Must be done BEFORE setting individual logger levels
      apply_default_level_overrides(config)

      # Configure named loggers from config AFTER default_level is finalized
      # CRITICAL: Logger instances need to be caches b/c SemanticLogger[]
      # creates new instances every time it's called. So we store references
      # to the configured loggers in @cached_loggers.
      @cached_loggers = {}
      config['loggers']&.each do |name, level|
        logger = SemanticLogger[name]
        logger.level = level.to_sym
        @cached_loggers[name] = logger
      end

      # Environment variable overrides for specific loggers
      apply_logger_level_overrides

      # Configure external library loggers
      configure_external_loggers

      # Log final effective configuration
      log_effective_configuration

      Onetime.ld "[Logging] Initialized SemanticLogger (level: #{SemanticLogger.default_level})"
    end

    private

    def load_logging_config
      # Get site path, fallback to current directory for tests
      site_path   = Onetime.conf.dig(:site, :path) || Dir.pwd
      config_path = File.join(site_path, 'etc', 'logging.yaml')

      if File.exist?(config_path)
        YAML.load_file(config_path) || {}
      else
        # Don't log error during boot, just return defaults
        {}
      end
    end

    # Apply environment variable overrides for default_level only
    # This must be called BEFORE setting individual logger levels
    def apply_default_level_overrides(config)
      # Step 1: Global default level override (affects only unconfigured loggers)
      if ENV['LOG_LEVEL']
        SemanticLogger.default_level = ENV['LOG_LEVEL'].to_sym
      end

      # Step 2: ONETIME_DEBUG=1 sets global default to debug
      # Does NOT override individual logger levels set in YAML config
      # This allows "debug by default" while respecting explicit logger config
      Onetime.debug? do
        SemanticLogger.default_level = :debug
      end
    end

    # Apply environment variable overrides for specific logger levels
    # This must be called AFTER setting individual logger levels from YAML
    def apply_logger_level_overrides
      # Environment variable precedence for individual loggers:
      # 1. DEBUG_* - individual quick flags per category
      # 2. DEBUG_LOGGERS - fine-grained per-logger control (highest precedence)
      #
      # These WILL override YAML config for specified loggers.

      # Step 1: Apply quick debug flags for individual categories first.
      # These provide a convenient way to enable debug logging for a component.
      apply_quick_debug_flag('Auth',    ENV['DEBUG_AUTH'])
      apply_quick_debug_flag('Session', ENV['DEBUG_SESSION'])
      apply_quick_debug_flag('HTTP',    ENV['DEBUG_HTTP'])
      apply_quick_debug_flag('Secret',  ENV['DEBUG_SECRET'])
      apply_quick_debug_flag('Sequel',  ENV['DEBUG_SEQUEL'])
      apply_quick_debug_flag('Rhales',  ENV['DEBUG_RHALES'])
      apply_quick_debug_flag('App',     ENV['DEBUG_APP'])

      # Step 2: Parse DEBUG_LOGGERS for fine-grained control.
      # This has the highest precedence and will override any previous setting.
      # Format: "Auth:debug,Secret:trace,Familia:warn" or "Auth=debug,Secret=trace"
      if ENV['DEBUG_LOGGERS']
        ENV['DEBUG_LOGGERS'].split(',').each do |spec|
          # Support both : and = separators
          logger_name, level = spec.split(/[:=]/, 2).map(&:strip)
          next unless logger_name && level

          # Get or create cached logger and set level
          cached_logger = (@cached_loggers[logger_name] ||= SemanticLogger[logger_name])
          cached_logger.level = level.to_sym
        end
      end

      # For external library logging levels, use DEBUG_LOGGERS instead:
      # DEBUG_LOGGERS=Familia:debug,Otto:trace,Rhales:warn
    end

    # Apply a quick debug flag to a specific logger
    def apply_quick_debug_flag(logger_name, env_value)
      return unless env_value

      # Get or create cached logger and set level
      cached_logger = (@cached_loggers[logger_name] ||= SemanticLogger[logger_name])
      cached_logger.level = :debug
    end

    # Log the final effective configuration
    # Shows which loggers differ from the default level
    def log_effective_configuration
      default = SemanticLogger.default_level
      overrides = []

      # Check all cached loggers for non-default levels
      @cached_loggers&.each do |name, logger|
        level = logger.level
        overrides << "#{name}=#{level}" if level != default
      end

      if overrides.any?
        $stderr.puts "[Logging] Effective: default=#{default}, overrides: #{overrides.join(', ')}"
      else
        $stderr.puts "[Logging] Effective: default=#{default} (no overrides)"
      end
    end

    # Configure external library loggers to use SemanticLogger
    #
    # Integrates third-party libraries with our SemanticLogger infrastructure,
    # ensuring consistent formatting and centralized log level control.
    #
    # Libraries configured:
    # - Familia: Redis ORM with SemanticLogger['Familia']
    # - Otto: Router framework with SemanticLogger['Otto']
    # - Rhales: Ruby SFC framework with SemanticLogger['Rhales']
    # - Sequel: Database connections with SemanticLogger['Sequel']
    #
    # Note: Some libraries don't support custom loggers (e.g., standard Redis gem).
    # For those, we rely on our own logging within wrapper code.
    #
    def configure_external_loggers
      # Familia Redis ORM - also responds to FAMILIA_DEBUG
      Familia.logger = SemanticLogger['Familia']

      # Otto router - also responds to OTTO_DEBUG
      Otto.logger = SemanticLogger['Otto']

      # Rhales manifold
      # Rhales.logger = SemanticLogger['Rhales']
      # Rhales.logger.level = :fatal

      # NOTE: Database logger is configured per-connection in
      # apps/web/auth/config/database.rb using db.loggers array
      # We'll update that file to use SemanticLogger instead of Logger.new

      configure_familia_hooks if defined?(Familia)
    end

    # Configure Familia audit hooks for operational visibility
    #
    # Registers hooks to capture Redis operations and Familia::Horreum lifecycle
    # events for audit trails and performance monitoring.
    #
    # Uses sampling in production to reduce log volume while preserving command
    # capture for tests.
    #
    def configure_familia_hooks
      familia_logger = SemanticLogger['Familia']

      # Configure sampling based on environment
      # - Development/Test: Log everything (nil = 100%)
      # - Production: Sample 1% of commands to reduce volume
      if defined?(Familia::DatabaseLogger)
        Familia::DatabaseLogger.sample_rate = case Onetime.conf[:environment]
        when 'production'
          ENV['FAMILIA_SAMPLE_RATE']&.to_f || 0.01  # 1% default
        when 'development'
          ENV['FAMILIA_SAMPLE_RATE']&.to_f || 0.1   # 10% default
        else
          # Log everything in test
        end
      end

      # Redis command performance tracking
      if Familia.respond_to?(:on_command)
        Familia.on_command do |cmd, duration, context|
          familia_logger.debug 'Redis command', {
            command: cmd,
            duration: duration,
            context: context
          }
        end
      end

      # Familia object lifecycle events (always logged, not sampled)
      return unless Familia.respond_to?(:on_lifecycle)

      Familia.on_lifecycle do |event, instance, context|
        familia_logger.debug 'Familia lifecycle', {
          event: event,
          class: instance.class.name,
          identifier: instance.respond_to?(:identifier) ? instance.identifier : nil,
          context: context
      end
    end
  end
end
