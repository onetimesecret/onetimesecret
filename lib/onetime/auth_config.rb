# lib/onetime/auth_config.rb
#
# frozen_string_literal: true

# Authentication configuration loader for Otto's Derived Identity Architecture

require 'yaml'
require 'erb'
require 'uri'
require 'singleton'
require_relative 'utils/config_resolver'
require_relative 'utils/enumerables'

module Onetime
  class AuthConfig
    include Singleton

    # Valid values for full.restrict_to — the single-auth-method override.
    RESTRICT_TO_VALUES = %w[password email_auth webauthn sso].freeze

    attr_reader :config, :path, :mode, :environment

    def initialize
      @environment = ENV['RACK_ENV'] || 'development'
      @path        = Onetime::Utils::ConfigResolver.resolve('auth')
      load_config
    end

    def configured?
      @config.is_a?(Hash)
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
      return {} unless auth_config

      auth_config['full'] || {}
    end

    # Simple mode configuration (Redis-only)
    def simple
      return {} unless auth_config

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

    # Whether SSO (external identity providers via OmniAuth) is enabled
    # Default: false
    #
    # Supports both 'sso' (new) and 'omniauth' (legacy) feature keys
    # so existing config files continue to work after the rename.
    def sso_enabled?
      feature_enabled?('sso', default: false) ||
        feature_enabled?('omniauth', default: false)
    end

    # DEPRECATED: Use sso_enabled? — retained for Rodauth integration files
    # that reference omniauth_enabled? (apps/web/auth/).
    alias omniauth_enabled? sso_enabled?

    # Whether organization-level SSO (per-domain SSO) is enabled.
    # Default: false
    #
    # When true, organizations with manage_sso entitlement can configure
    # domain-specific SSO via CustomDomain::SsoConfig. Credentials are
    # injected at runtime by OmniAuthTenant hook rather than requiring
    # platform-level environment variables.
    #
    # Reads from ORGS_SSO_ENABLED env var via features.organizations.sso_enabled
    # in site config (etc/config.yaml).
    def orgs_sso_enabled?
      OT.conf.dig('features', 'organizations', 'sso_enabled') == true
    end

    # The login-page restriction, if any.
    # Returns one of RESTRICT_TO_VALUES ('password', 'email_auth',
    # 'webauthn', 'sso') or nil when all enabled methods are shown.
    #
    # Guards:
    # - Returns nil in simple mode or when the value is unrecognised.
    # - For 'sso': requires sso_enabled? and at least one provider.
    # - For 'email_auth': requires email_auth_enabled?.
    # - For 'webauthn': requires webauthn_enabled?.
    # - 'password' has no prerequisite (passwords are always available
    #   in full mode).
    def restrict_to
      return nil unless full_enabled?

      value = full['restrict_to'].to_s.strip
      # Legacy fallback: configs that still use sso.sso_only instead of restrict_to
      value = 'sso' if value.empty? && legacy_sso_only?

      return nil unless RESTRICT_TO_VALUES.include?(value)

      # Ensure the restriction refers to an actually enabled method.
      case value
      when 'sso'
        return nil unless sso_enabled? && sso_providers.any?
      when 'email_auth'
        return nil unless email_auth_enabled?
      when 'webauthn'
        return nil unless webauthn_enabled?
      end

      value
    end

    # Whether SSO-only mode is active.
    # When true, password-based account management is disabled (destroy
    # account, change password, change email). Users must manage their
    # credentials through the SSO identity provider.
    def sso_only_enabled?
      restrict_to == 'sso'
    end

    # Whether password-only mode is active.
    # When true, only the password form is shown on the login page;
    # other enabled auth methods (SSO, WebAuthn, magic links) are hidden.
    def password_only_enabled?
      restrict_to == 'password'
    end

    # Whether email-auth-only (magic links) mode is active.
    # When true, only the email link form is shown on the login page.
    def email_auth_only_enabled?
      restrict_to == 'email_auth'
    end

    # Whether WebAuthn-only mode is active.
    # When true, only biometric/security-key authentication is shown.
    def webauthn_only_enabled?
      restrict_to == 'webauthn'
    end

    # SSO display name (e.g., "Zitadel", "Okta", "Azure AD")
    # Used for "Sign in with X" button text
    # Returns nil if not configured (frontend will use generic "SSO")
    #
    # DEPRECATED: In multi-provider context, each provider carries its own
    # display_name. Use sso_providers instead.
    def sso_display_name
      return nil unless sso_enabled?

      name = sso_config['sso_display_name']
      name.to_s.strip.empty? ? nil : name
    end

    # Whether custom domains without their own CustomDomain::SsoConfig
    # can fall back to platform ENV-based SSO credentials.
    #
    # Default: false (require explicit per-domain SSO configuration)
    def allow_platform_fallback_for_tenants?
      sso_config['allow_platform_fallback_for_tenants'] == true
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
      return nil unless sso_enabled?

      ENV.fetch('OIDC_ROUTE_NAME', 'oidc')
    end

    # All configured SSO providers, built dynamically from env var presence.
    # Returns an array of hashes: [{ 'route_name' => 'oidc', 'display_name' => 'SSO' }, ...]
    # Each entry corresponds to a provider whose required env vars are present.
    # Returns empty array if SSO is disabled or no providers are configured.
    def sso_providers
      return [] unless sso_enabled?

      provider_definitions.filter_map do |defn|
        next unless defn[:required_vars].all? { |var| env_present?(var) }

        display = ENV.fetch(defn[:display_var], nil) || defn[:display_default]
        {
          'route_name' => ENV.fetch(defn[:route_var], defn[:route_default]),
          'display_name' => display,
        }
      end
    end

    # The SSO identity-provider origins that must be allowed in the CSP
    # form-action directive.
    #
    # Since otto 2.5+, the app emits a CSP header with `form-action 'self'`.
    # Chromium enforces form-action across the whole redirect chain, so the
    # SSO flow — a DOM form POST to /auth/sso/:provider that 302-redirects to
    # the IdP (e.g. login.microsoftonline.com) — is blocked unless the IdP
    # origin is present in form-action. This returns those origins so the
    # router can widen the directive at boot.
    #
    # Provider-derived origins reuse the SAME gating as #sso_providers (SSO
    # feature enabled AND the provider's required env vars present), so they
    # can never drift from the providers that actually register. The
    # SSO_FORM_ACTION_ORIGINS override is merged in unconditionally — it covers
    # sovereign clouds, an OIDC issuer that differs from its authorization
    # endpoint, and org-level SSO whose issuers are unknown at boot.
    #
    # Returns a de-duplicated Array of origin strings (scheme://host[:port]),
    # or [] when nothing is configured. Side-effect free and safe to call at
    # router-build time (no auth-app boot required).
    def sso_form_action_origins
      provider_origins = active_provider_origins
      override_origins = override_form_action_origins

      # An override set with zero auto-derived provider origins (SSO disabled or
      # no active providers) is a config smell worth surfacing: form-action is
      # being widened without any provider that actually registers.
      if provider_origins.empty? && !ENV.fetch('SSO_FORM_ACTION_ORIGINS', '').to_s.strip.empty?
        OT.lw '[auth_config] SSO_FORM_ACTION_ORIGINS is widening CSP form-action but ' \
              'no SSO provider origins are active (SSO disabled or no active providers)'
      end

      (provider_origins + override_origins).uniq
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

    # Whether the legacy sso.sso_only flag is set in config.
    # Used as a fallback by #restrict_to for configs that predate
    # the restrict_to key.
    def legacy_sso_only?
      sso_config['sso_only'] == true
    end

    # SSO configuration section from full mode config.
    # Contains sso_display_name (and legacy sso_only).
    #
    # Falls back to legacy layout where sso_display_name lived
    # under features, so existing config files keep working.
    def sso_config
      section = full['sso']
      return section if section.is_a?(Hash)

      # Legacy: sso_display_name was under features, sso_only read from ENV
      {
        'sso_display_name' => features['sso_display_name'],
        'sso_only' => ENV['AUTH_SSO_ONLY'] == 'true',
      }
    end

    # Generic helper to check if a feature is enabled in full mode.
    # Returns false if not in full mode, otherwise fetches the feature
    # flag from config, falling back to the provided default.
    def feature_enabled?(key, default:)
      return false unless full_enabled?

      features.fetch(key, default)
    end

    # Provider definitions for sso_providers. Each entry defines the env
    # vars that gate the provider and where to read its route/display names.
    #
    # idp_origin / idp_origin_from feed #sso_form_action_origins: a static
    # :idp_origin for providers whose IdP host is fixed, or :idp_origin_from
    # naming an env var whose URL the origin is derived from (OIDC's issuer).
    # ENTRA is static because the OmniAuth strategy hard-pins the commercial
    # cloud (login.microsoftonline.com); there is no sovereign-cloud authority
    # env in this app — use SSO_FORM_ACTION_ORIGINS for those.
    def provider_definitions
      [
        {
          required_vars: %w[OIDC_ISSUER OIDC_CLIENT_ID],
          route_var: 'OIDC_ROUTE_NAME',
          route_default: 'oidc',
          display_var: 'OIDC_DISPLAY_NAME',
          display_default: sso_display_name || 'SSO',
          idp_origin_from: 'OIDC_ISSUER',
        },
        {
          required_vars: %w[ENTRA_TENANT_ID ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET],
          route_var: 'ENTRA_ROUTE_NAME',
          route_default: 'entra',
          display_var: 'ENTRA_DISPLAY_NAME',
          display_default: 'Microsoft',
          idp_origin: 'https://login.microsoftonline.com',
        },
        {
          required_vars: %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET],
          route_var: 'GOOGLE_ROUTE_NAME',
          route_default: 'google',
          display_var: 'GOOGLE_DISPLAY_NAME',
          display_default: 'Google',
          idp_origin: 'https://accounts.google.com',
        },
        {
          required_vars: %w[GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET],
          route_var: 'GITHUB_ROUTE_NAME',
          route_default: 'github',
          display_var: 'GITHUB_DISPLAY_NAME',
          display_default: 'GitHub',
          idp_origin: 'https://github.com',
        },
      ]
    end

    # Origins for the providers that pass #sso_providers' gate (SSO enabled and
    # all required env vars present). Reuses provider_definitions so it can
    # never register an origin for a provider that would not register.
    # filter_map drops a provider whose origin cannot be resolved (e.g. a
    # malformed OIDC_ISSUER), so a bad issuer is skipped, never raised.
    def active_provider_origins
      return [] unless sso_enabled?

      provider_definitions.filter_map do |defn|
        next unless defn[:required_vars].all? { |var| env_present?(var) }

        provider_origin(defn)
      end
    end

    # Resolve a single provider definition to its IdP origin: a static
    # :idp_origin, or one derived from the URL in the env var named by
    # :idp_origin_from. Returns nil when unresolvable.
    def provider_origin(defn)
      return defn[:idp_origin] if defn[:idp_origin]
      return origin_from_url(ENV.fetch(defn[:idp_origin_from], nil)) if defn[:idp_origin_from]

      nil
    end

    # The SSO_FORM_ACTION_ORIGINS override: a space-separated origin list,
    # merged into #sso_form_action_origins independent of any provider gating.
    #
    # Each token is routed through #origin_from_url and filter_map-dropped
    # unless it resolves to a clean http(s) origin. Passing raw tokens straight
    # into the CSP form-action directive is unsafe: a token like
    # "https://idp.example.com;" or "https://a b.com" would inject into the
    # header and otto's per-request reject_injection! would raise, 500-ing every
    # request. Dropped tokens are logged so a misconfiguration is visible.
    def override_form_action_origins
      ENV.fetch('SSO_FORM_ACTION_ORIGINS', '').to_s.split.filter_map do |token|
        origin = origin_from_url(token)
        OT.lw "[auth_config] dropping invalid SSO_FORM_ACTION_ORIGINS token: #{token.inspect}" if origin.nil?
        origin
      end
    end

    # Derive an origin (scheme://host[:port]) from a URL, omitting a default
    # port (80/443). Returns nil for a blank, schemeless, hostless, or
    # otherwise malformed URL — never raises. Note that URI.parse sets #host to
    # an empty string (not nil) for a scheme-present, hostless URL such as
    # "https://" or "https:///path", so an empty/whitespace host is treated the
    # same as nil to avoid emitting a degenerate "https://" origin.
    def origin_from_url(url)
      str = url.to_s.strip
      return nil if str.empty?

      uri = URI.parse(str)

      # Only http(s) may widen the CSP form-action directive. Plain http is
      # kept on purpose: internal OIDC providers commonly run without TLS.
      return nil unless %w[http https].include?(uri.scheme&.downcase)

      host = uri.host.to_s.strip
      return nil if host.empty?

      # Reject a host carrying CSP-hostile characters (whitespace, ';', ',',
      # quotes, brackets, control chars). URI.parse keeps a trailing ';' on the
      # host ("idp.example.com;" from "https://idp.example.com;"), and such an
      # origin would break the form-action directive — otto's per-request
      # reject_injection! raises, 500-ing every request. Guard here so a
      # returned origin is always CSP-safe.
      return nil if host.match?(/[\s;,'"()<>]/) || host.match?(/[\x00-\x1f]/)

      origin  = "#{uri.scheme}://#{host}"
      origin += ":#{uri.port}" if uri.port && uri.port != uri.default_port
      origin
    rescue URI::Error
      nil
    end

    # Check if an environment variable is present and non-empty
    def env_present?(name)
      val = ENV.fetch(name, nil)
      !val.nil? && !val.empty?
    end

    def load_config
      unless @path && File.exist?(@path)
        @config = nil
        return
      end

      defaults_file = Onetime::Utils::ConfigResolver.defaults_path('auth')
      base_config   = if defaults_file && defaults_file != @path
        load_yaml_from(defaults_file)
      else
        {}
      end

      env_config = load_yaml_from(@path)

      @config = if base_config.empty?
        env_config
      else
        Onetime::Utils::Enumerables.deep_merge(base_config, env_config, preserve_nils: false)
      end
    rescue StandardError => ex
      handle_config_error(ex)
    end

    def load_yaml_from(path)
      erb_template = ERB.new(File.read(path))
      yaml_content = erb_template.result(binding)
      YAML.safe_load(yaml_content, symbolize_names: false) || {}
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
