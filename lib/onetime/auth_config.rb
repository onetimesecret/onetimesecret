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
      @path        = Onetime::Utils::ConfigResolver.resolve('auth')
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

    # Argon2 secret key (pepper) for password hashing defense-in-depth.
    # Returns nil when unset — argon2id works fine without a pepper.
    def argon2_secret
      full['argon2_secret']
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

    # Whether brute force lockout protection is enabled
    # Default: true (when full mode is enabled)
    def lockout_enabled?
      feature_enabled?('lockout', default: true)
    end

    # Whether password strength requirements are enabled
    # Default: true (when full mode is enabled)
    def password_requirements_enabled?
      feature_enabled?('password_requirements', default: true)
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

    # Whether OmniAuth (external identity providers via OIDC) is enabled
    # Default: false
    def omniauth_enabled?
      feature_enabled?('omniauth', default: false)
    end

    # SSO display name (e.g., "Zitadel", "Okta", "Azure AD")
    # Used for "Sign in with X" button text
    # Returns nil if not configured (frontend will use generic "SSO")
    #
    # DEPRECATED: In multi-provider context, each provider carries its own
    # display_name. Use sso_providers instead.
    def sso_display_name
      return nil unless omniauth_enabled?

      name = features['sso_display_name']
      name.to_s.strip.empty? ? nil : name
    end

    # DEPRECATED: Use sso_display_name
    def omniauth_provider_name
      sso_display_name
    end

    # OmniAuth route name for building the SSO callback URL
    # Defaults to 'oidc' if OIDC_ROUTE_NAME is not set
    # Used by frontend to construct /auth/sso/{route_name} paths
    #
    # DEPRECATED: Use sso_providers instead (returns array of providers
    # each with their own route_name).
    def omniauth_route_name
      return nil unless omniauth_enabled?

      ENV.fetch('OIDC_ROUTE_NAME', 'oidc')
    end

    # All configured SSO providers, built dynamically from env var presence.
    # Returns an array of hashes: [{ 'route_name' => 'oidc', 'display_name' => 'SSO' }, ...]
    # Each entry corresponds to a provider whose required env vars are present.
    # Returns empty array if omniauth is disabled or no providers are configured.
    def sso_providers
      return [] unless omniauth_enabled?

      provider_definitions.filter_map do |defn|
        next unless defn[:required_vars].all? { |var| env_present?(var) }

        display = ENV.fetch(defn[:display_var], nil) || defn[:display_default]
        {
          'route_name' => ENV.fetch(defn[:route_var], defn[:route_default]),
          'display_name' => display,
        }
      end
    end

    # DEPRECATED: Use email_auth_enabled?
    def magic_links_enabled?
      email_auth_enabled?
    end

    # Reload configuration (useful for testing)
    def reload!
      @path = Onetime::Utils::ConfigResolver.resolve('auth')
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

    # Provider definitions for sso_providers. Each entry defines the env
    # vars that gate the provider and where to read its route/display names.
    def provider_definitions
      [
        {
          required_vars: %w[OIDC_ISSUER OIDC_CLIENT_ID],
          route_var: 'OIDC_ROUTE_NAME', route_default: 'oidc',
          display_var: 'OIDC_DISPLAY_NAME', display_default: sso_display_name || 'SSO',
        },
        {
          required_vars: %w[ENTRA_TENANT_ID ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET],
          route_var: 'ENTRA_ROUTE_NAME', route_default: 'entra',
          display_var: 'ENTRA_DISPLAY_NAME', display_default: 'Microsoft',
        },
        {
          required_vars: %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET],
          route_var: 'GOOGLE_ROUTE_NAME', route_default: 'google',
          display_var: 'GOOGLE_DISPLAY_NAME', display_default: 'Google',
        },
        {
          required_vars: %w[GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET],
          route_var: 'GITHUB_ROUTE_NAME', route_default: 'github',
          display_var: 'GITHUB_DISPLAY_NAME', display_default: 'GitHub',
        },
      ]
    end

    # Check if an environment variable is present and non-empty
    def env_present?(name)
      val = ENV.fetch(name, nil)
      !val.nil? && !val.empty?
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

      raise ConfigError,
        config_error_message(
          'Configuration file not found',
          "File does not exist: #{@path}",
        )
    end

    def handle_config_error(exception)
      # @config = default_config
      raise ConfigError,
        config_error_message(
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
