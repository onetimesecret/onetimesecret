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

    attr_reader :config, :path, :mode, :environment

    def initialize
      @environment = ENV['RACK_ENV'] || 'development'
      @path = Onetime::Utils::ConfigResolver.resolve('auth')
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

    # Full mode database URL (from config only, env vars captured in auth.yaml)
    def database_url
      full['database_url'] || 'sqlite://data/auth.db'
    end

    # Full mode database URL for migrations (with elevated privileges)
    # Returns nil if not explicitly configured - caller must handle fallback
    def database_url_migrations
      full['database_url_migrations']
    end

    # Whether full mode is enabled (Rodauth-based)
    def full_enabled?
      mode == 'full'
    end

    # Whether simple mode is enabled (Redis-only)
    def simple_enabled?
      mode == 'simple'
    end

    # Feature flags hash from full mode config
    def features
      full['features'] || {}
    end

    # Whether hardening features are enabled (lockout, password requirements)
    # Default: true (when full mode is enabled)
    def hardening_enabled?
      feature_enabled?('hardening', default: true)
    end

    # Whether active sessions tracking is enabled
    # Default: true (when full mode is enabled)
    def active_sessions_enabled?
      feature_enabled?('active_sessions', default: true)
    end

    # Whether remember me functionality is enabled
    # Default: true (when full mode is enabled)
    def remember_me_enabled?
      feature_enabled?('remember_me', default: true)
    end

    # Whether verify account (email verification) is enabled
    # Default: true (when full mode is enabled), but false in test environment
    def verify_account_enabled?
      feature_enabled?('verify_account', default: true)
    end

    # Whether MFA is enabled (TOTP, recovery codes)
    # Default: false
    def mfa_enabled?
      feature_enabled?('mfa', default: false)
    end

    # Whether email auth is enabled (passwordless login via email, aka magic links)
    # Default: false
    def email_auth_enabled?
      feature_enabled?('email_auth', default: false)
    end

    # Whether WebAuthn (biometrics, security keys) is enabled
    # Default: false
    def webauthn_enabled?
      feature_enabled?('webauthn', default: false)
    end

    # DEPRECATED: Use hardening_enabled?, active_sessions_enabled?, remember_me_enabled?
    def security_features_enabled?
      hardening_enabled? && active_sessions_enabled? && remember_me_enabled?
    end

    # DEPRECATED: Use email_auth_enabled?
    def magic_links_enabled?
      email_auth_enabled?
    end

    # Reload configuration (useful for testing)
    # Also picks up any changes to AuthConfig.path
    def reload!
      @path = self.class.path || File.join(Onetime::HOME, 'etc/auth.yaml')
      load_config
      self
    end

    private

    # Generic helper to check if a feature is enabled in full mode.
    # Returns false if not in full mode, otherwise fetches the feature
    # flag from config, falling back to the provided default.
    def feature_enabled?(key, default:)
      return false unless full_enabled?

      features.fetch(key, default)
    end

    def load_config
      validate_config_file_exists!

      erb_template = ERB.new(File.read(@path))
      yaml_content = erb_template.result(binding)
      @config      = YAML.safe_load(yaml_content, symbolize_names: false)
    rescue StandardError => ex
      handle_config_error(ex)
    end

    def validate_config_file_exists!
      return if File.exist?(@path)

      raise ConfigError, config_error_message(
        'Configuration file not found',
        "File does not exist: #{@path}",
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
        1. Ensure the configuration file exists at: #{@path}
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
