# lib/onetime/auth_config.rb
#
# frozen_string_literal: true

# Authentication configuration loader for Otto's Derived Identity Architecture

require 'yaml'
require 'erb'
require 'singleton'
require_relative 'utils/config_resolver'

module Onetime
  class AuthConfig
    include Singleton

    class << self
    end

    attr_reader :config, :mode, :environment

    def initialize
      @environment = ENV['RACK_ENV'] || 'development'
      @config_file = Onetime::Utils::ConfigResolver.resolve('auth')
      load_config
    end

    # Main authentication mode: 'simple' or 'full'
    #
    # The environment variable is capture in the config file
    def mode
      return nil if config.nil?
      return config['mode'] if config['mode'].match?(/\A(?:simple|full)\z/)

      'simple'
    end

    # Full mode configuration (Rodauth-based)
    def full
      auth_config['full'] || {}
    end

    # Simple mode configuration (Redis-only)
    def simple
      auth_config['simple'] || {}
    end

    # NOTE: Session configuration has been moved to site config (site.session)
    # Use Onetime.session_config instead of Onetime.auth_config.session

    # Full mode database URL
    def database_url
      ENV['AUTH_DATABASE_URL'] || full['database_url'] || 'sqlite://data/auth.db'
    end

    # Full mode database URL for migrations (with elevated privileges)
    # Falls back to database_url if not set
    def database_url_migrations
      full['database_url_migrations'] || database_url
    end

    # Whether full mode is enabled (Rodauth-based)
    def full_enabled?
      mode == 'full'
    end

    # Whether simple mode is enabled (Redis-only)
    def simple_enabled?
      mode == 'simple'
    end

    # Reload configuration (useful for testing)
    # Also picks up any changes to AuthConfig.path
    def reload!
      @config_file = self.class.path || File.join(Onetime::HOME, 'etc/auth.yaml')
      load_config
      self
    end

    private

    def load_config
      validate_config_file_exists!

      erb_template = ERB.new(File.read(@config_file))
      yaml_content = erb_template.result(binding)
      @config      = YAML.safe_load(yaml_content, symbolize_names: false)
    rescue StandardError => ex
      handle_config_error(ex)
    end

    def validate_config_file_exists!
      return if File.exist?(@config_file)

      raise ConfigError, config_error_message(
        'Configuration file not found',
        "File does not exist: #{@config_file}",
      )
    end

    def handle_config_error(exception)
      # @config = default_config
      raise ConfigError, config_error_message(
        "Failed to load authentication configuration: #{exception.message}",
        exception.backtrace&.first,
      )
    end

    def config_error_message(primary_error, detail = nil)
      message = <<~ERROR
        #{primary_error}
        #{detail if detail}

        To fix this issue:
        1. Ensure the configuration file exists at: #{@config_file}
        2. Copy etc/defaults/auth.defaults.yaml if needed
        3. Verify YAML syntax is valid
        4. Check file permissions
      ERROR

      message.strip
    end

    def auth_config
      @config
    end
  end

  # Convenience method for accessing auth configuration
  def self.auth_config
    AuthConfig.instance
  end
end
