# lib/onetime/auth_config.rb
# Authentication configuration loader for Otto's Derived Identity Architecture

require 'yaml'
require 'erb'
require 'singleton'

module Onetime
  class AuthConfig
    include Singleton

    attr_reader :config, :mode, :environment

    def initialize
      @environment = ENV['RACK_ENV'] || 'development'
      @config_file = File.join(Onetime::HOME, 'etc/auth.yml')
      load_config
    end

    # Main authentication mode: 'basic' or 'advanced'
    def mode
      # Environment variable takes precedence
      return ENV['AUTHENTICATION_MODE'] if ENV['AUTHENTICATION_MODE'] && %w[basic advanced].include?(ENV['AUTHENTICATION_MODE'])

      # Check configuration file
      auth_config['mode'] || 'basic'
    end

    # Advanced configuration
    def advanced
      auth_config['advanced'] || {}
    end

    # Basic mode configuration
    def basic
      auth_config['basic'] || {}
    end

    # Session configuration
    def session
      session_config = auth_config['session'] || {}

      # Apply environment-specific SSL setting
      session_config['secure'] = ssl_enabled? if session_config['secure'].nil?

      session_config
    end

    # Advanced database URL
    def database_url
      ENV['DATABASE_URL'] || advanced['database_url'] || 'sqlite://data/auth.db'
    end

    # Whether Advanced mode is enabled
    def advanced_enabled?
      mode == 'advanced'
    end

    # Whether basic mode is enabled
    def basic_enabled?
      mode == 'basic'
    end

    # Reload configuration (useful for testing)
    def reload!
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
      @config = default_config
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

    def ssl_enabled?
      # Check if SSL is enabled in OT configuration
      OT.conf&.dig('site', 'ssl') || @environment == 'production'
    end
  end

  # Convenience method for accessing auth configuration
  def self.auth_config
    AuthConfig.instance
  end
end
