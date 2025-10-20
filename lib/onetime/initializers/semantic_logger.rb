# frozen_string_literal: true

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
      site_path = Onetime.conf.dig(:site, :path) || Dir.pwd
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
          logger_name, level = spec.split(':')
          SemanticLogger[logger_name].level = level.to_sym
        end
      end

      # Quick debug flags for each strategic category
      SemanticLogger['Auth'].level    = :debug if ENV['DEBUG_AUTH']
      SemanticLogger['Session'].level = :debug if ENV['DEBUG_SESSION']
      SemanticLogger['HTTP'].level    = :debug if ENV['DEBUG_HTTP']
      SemanticLogger['Familia'].level = :debug if ENV['DEBUG_FAMILIA']
      SemanticLogger['Otto'].level    = :debug if ENV['DEBUG_OTTO']
      SemanticLogger['Rhales'].level  = :debug if ENV['DEBUG_RHALES']
      SemanticLogger['Sequel'].level  = :debug if ENV['DEBUG_SEQUEL']
      SemanticLogger['Secret'].level  = :debug if ENV['DEBUG_SECRET']
    end

    # Configure external library loggers to use SemanticLogger
    #
    # Integrates third-party libraries with our SemanticLogger infrastructure,
    # ensuring consistent formatting and centralized log level control.
    #
    # Libraries configured:
    # - Familia: Redis ORM with SemanticLogger['Familia']
    # - Otto: Router framework with SemanticLogger['Otto']
    # - Sequel: Database connections with SemanticLogger['Sequel']
    #
    # Note: Some libraries don't support custom loggers (e.g., Rhales, standard
    # Redis gem). For those, we rely on our own logging within wrapper code.
    #
    def configure_external_loggers
      # Familia Redis ORM - supports Familia.logger =
      if defined?(Familia)
        Familia.logger = SemanticLogger['Familia']
      end

      # Otto router - supports Otto.logger =
      if defined?(Otto)
        Otto.logger = SemanticLogger['Otto']
      end

      # Sequel database - configure logger on database instances
      # This is typically done when creating the connection, but we can
      # set a default for any existing connections
      if defined?(Sequel) && defined?(Auth::Config::Database)
        # Note: Database logger is configured per-connection in
        # apps/web/auth/config/database.rb using db.loggers array
        # We'll update that file to use SemanticLogger instead of Logger.new
      end
    end
  end
end
