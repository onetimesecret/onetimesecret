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
    def configure_logging
      config = load_logging_config

      # Base configuration
      SemanticLogger.default_level = config['default_level']&.to_sym || :info
      SemanticLogger.add_appender(
        io: $stdout,
        formatter: config['formatter']&.to_sym || :color,
      )

      # Configure named loggers from config
      config['loggers']&.each do |name, level|
        SemanticLogger[name].level = level.to_sym
      end

      # Environment variable overrides
      apply_environment_overrides

      # Configure external library loggers
      configure_external_loggers

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

    def apply_environment_overrides
      # Global level override
      if ENV['LOG_LEVEL']
        SemanticLogger.default_level = ENV['LOG_LEVEL'].to_sym
      end

      # Parse DEBUG_LOGGERS: "Auth:debug,Secret:trace"
      if ENV['DEBUG_LOGGERS']
        ENV['DEBUG_LOGGERS'].split(',').each do |spec|
          logger_name, level                = spec.split(':')
          SemanticLogger[logger_name].level = level.to_sym
        end
      end

      # Quick debug flags for application categories only
      # External libraries (Familia, Otto) use their own debug flags
      SemanticLogger['Auth'].level    = :debug if ENV['DEBUG_AUTH']
      SemanticLogger['Session'].level = :debug if ENV['DEBUG_SESSION']
      SemanticLogger['HTTP'].level    = :debug if ENV['DEBUG_HTTP']
      SemanticLogger['Secret'].level  = :debug if ENV['DEBUG_SECRET']

      # For external library logging levels, use DEBUG_LOGGERS instead:
      # DEBUG_LOGGERS=Sequel:debug,Rhales:trace
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
      Rhales.logger = SemanticLogger['Rhales']

      # Sequel database - configure logger on database instances
      # This is typically done when creating the connection, but we can
      # set a default for any existing connections
      nil unless defined?(Sequel) && defined?(Auth::Config::Database)
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
          nil  # Log everything in test
        end
      end

      # Redis command performance tracking
      Familia.on_command do |cmd, duration_ms, context|
        familia_logger.debug "Redis command",
          command: cmd,
          duration_ms: duration_ms,
          context: context
      end if Familia.respond_to?(:on_command)

      # Familia object lifecycle events (always logged, not sampled)
      Familia.on_lifecycle do |event, instance, context|
        familia_logger.debug "Familia lifecycle",
          event: event,
          class: instance.class.name,
          identifier: instance.respond_to?(:identifier) ? instance.identifier : nil,
          context: context
      end if Familia.respond_to?(:on_lifecycle)
    end
  end
end
