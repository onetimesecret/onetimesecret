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
      SemanticLogger['Secret'].level  = :debug if ENV['DEBUG_SECRET']
    end
  end
end
