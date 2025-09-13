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
      @config_file = File.join(File.dirname(__FILE__), '../../etc/auth.yml')
      load_config
    end

    # Main authentication mode: 'basic' or 'rodauth'
    def mode
      # Environment variable takes precedence
      return ENV['AUTHENTICATION_MODE'] if ENV['AUTHENTICATION_MODE'] && %w[basic rodauth].include?(ENV['AUTHENTICATION_MODE'])

      # Check configuration file
      auth_config['mode'] || 'basic'
    end

    # Rodauth configuration
    def rodauth
      auth_config['rodauth'] || {}
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

    # Rodauth database URL
    def database_url
      ENV['DATABASE_URL'] || rodauth['database_url'] || 'sqlite://data/auth.db'
    end

    # Whether Rodauth mode is enabled
    def rodauth_enabled?
      mode == 'rodauth'
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
      if File.exist?(@config_file)
        erb_template = ERB.new(File.read(@config_file))
        yaml_content = erb_template.result(binding)
        @config      = YAML.safe_load(yaml_content, symbolize_names: false)
      else
        @config = default_config
        warn "[AuthConfig] Configuration file not found: #{@config_file}, using defaults"
      end
    rescue StandardError => ex
      @config = default_config
      warn "[AuthConfig] Error loading configuration: #{ex.message}, using defaults"
    end

    def auth_config
      # Merge base config with environment-specific overrides
      base_config = @config['authentication'] || {}
      env_config  = @config[@environment]&.dig('authentication') || {}

      deep_merge(base_config, env_config)
    end

    def ssl_enabled?
      # Check if SSL is enabled in OT configuration
      OT.conf&.dig('site', 'ssl') || @environment == 'production'
    end

    def default_config
      {
        'authentication' => {
          'mode' => 'basic',
          'rodauth' => {
            'deployment' => 'local',
            'database_url' => 'sqlite://data/auth.db',
            'features' => %w[login logout create_account close_account change_password reset_password],
            'security' => {
              'password_minimum_length' => 8,
              'max_invalid_logins' => 5,
              'session_expire_after' => 86_400,
            },
          },
          'basic' => {
            'password_hash_cost' => 12,
            'session_timeout' => 86_400,
          },
          'session' => {
            'redis_url' => 'redis://localhost:6379/0',
            'expire_after' => 86_400,
            'key' => 'onetime.session',
            'secure' => ssl_enabled?,
            'httponly' => true,
            'same_site' => 'lax',
            'redis_prefix' => 'session',
          },
        },
      }
    end

    def deep_merge(base_hash, override_hash)
      base_hash.merge(override_hash) do |_key, base_value, override_value|
        if base_value.is_a?(Hash) && override_value.is_a?(Hash)
          deep_merge(base_value, override_value)
        else
          override_value
        end
      end
    end
  end

  # Convenience method for accessing auth configuration
  def self.auth_config
    AuthConfig.instance
  end
end
