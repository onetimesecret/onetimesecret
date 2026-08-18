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
require_relative 'sso_provider/registry'

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
    #
    # A BLANK value is treated as unset. The config file renders this key from
    # ENV (`ENV['AUTH_DATABASE_URL'] || <default>`), and an exported-but-empty
    # AUTH_DATABASE_URL is truthy in Ruby — so without this normalization the
    # empty string wins over the default and reaches Sequel.connect(''), where
    # URI.parse('').scheme is nil and adapter_class raises a bare
    # `NoMethodError: undefined method 'to_sym' for nil`.
    def database_url
      presence(full['database_url']) || 'sqlite://data/auth.db'
    end

    # Full mode database URL for migrations (with elevated privileges)
    # Returns nil if not explicitly configured - caller must handle fallback
    # (blank is treated as unset, same as #database_url)
    def database_url_migrations
      presence(full['database_url_migrations'])
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

    # Whether WebAuthn passwordless signup is enabled: verifying a new account
    # sets up a passkey instead of a password (Rodauth webauthn_verify_account).
    # Only consulted when webauthn_enabled? — config.rb loads the WebAuthn
    # feature module only then. Driven by AUTH_WEBAUTHN_VERIFY_ACCOUNT
    # (== 'true' semantics, rendered in auth.defaults.yaml).
    # Default: false
    def webauthn_verify_account_enabled?
      feature_enabled?('webauthn_verify_account', default: false)
    end

    # Whether passkey autofill (browser conditional UI) on the login form is
    # enabled (Rodauth webauthn_autofill). Only consulted when
    # webauthn_enabled?. Driven by AUTH_WEBAUTHN_AUTOFILL (== 'true'
    # semantics, rendered in auth.defaults.yaml).
    # Default: false
    def webauthn_autofill_enabled?
      feature_enabled?('webauthn_autofill', default: false)
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

    # The global sign-in restriction, if any. An access control over which
    # methods work on this install, not a login-page display preference
    # (ADR-034#restrict-to-is-an-access-control-not-a-display-preference).
    # Returns one of RESTRICT_TO_VALUES ('password', 'email_auth',
    # 'webauthn', 'sso'), or nil ONLY when no restriction is configured
    # (and always nil in simple mode, where restrict_to has no meaning).
    #
    # It NEVER returns nil to express "the configured restriction could not
    # be honored" (ADR-034#degradation-is-fail-closed, #4140). That was a silent fail-OPEN: every
    # caller reads nil as "unrestricted", so an install whose restricted
    # method was unavailable widened to standard mode and re-exposed exactly
    # the methods the operator restricted away — with no log line at all.
    #
    # Availability is handled in two separate places instead:
    # - Boot: #validate_restrict_to! raises OT::ConfigError when the named
    #   method's prerequisites are already known to be unmet. Validate once,
    #   loudly; this reader never raises, so a request path stays cheap.
    # - Runtime: unavailability only discoverable AFTER boot keeps the
    #   restriction in place, so callers degrade fail-CLOSED (sign-in
    #   unavailable / method-specific notice) instead of widening. See
    #   #restrict_to_available?.
    #
    # An unrecognised value still reads as nil here, but it can only survive
    # boot when validation did not run (partial boot); #validate_restrict_to!
    # rejects it.
    def restrict_to
      return nil unless full_enabled?

      value = configured_restrict_to
      RESTRICT_TO_VALUES.include?(value) ? value : nil
    end

    # Whether the configured restriction's backing method is actually usable
    # right now. Consumers use this to degrade fail-closed: a restriction
    # whose method is unavailable means sign-in is unavailable, never that
    # sign-in widens to the other methods (ADR-034#degradation-is-fail-closed).
    #
    # Returns true when nothing is restricted (nothing to be unavailable).
    def restrict_to_available?
      value = restrict_to
      return true if value.nil?

      restrict_to_unmet_prerequisite(value).nil?
    end

    # Boot-time validation of the global restriction (ADR-034#degradation-is-fail-closed, #4140).
    #
    # Raises OT::ConfigError — a fatal boot error — when full.restrict_to
    # names a method whose prerequisites the system can already determine are
    # unmet, or names a value that is not a valid restriction at all. A
    # refused boot is the loud failure: it reaches the operator holding the
    # config file at deploy time. (Contrast #4062's set-but-blank admin host
    # allowlist, which warns because of a lockout trap; that argument was
    # considered and overruled here — the trap on this path is a silent
    # runtime widen, not a refused boot.)
    #
    # Idempotent: the result is memoized so repeated boot phases (and
    # #reload! in tests) behave predictably.
    #
    # @raise [Onetime::ConfigError] when the configured restriction cannot be honored
    # @return [String, nil] the validated restriction, or nil when none is configured
    def validate_restrict_to!
      return @validate_restrict_to if defined?(@validate_restrict_to)

      @validate_restrict_to = nil
      return nil unless full_enabled?

      value = configured_restrict_to
      return nil if value.empty?

      raise Onetime::ConfigError, restrict_to_error_message(value, nil) unless RESTRICT_TO_VALUES.include?(value)

      unmet = restrict_to_unmet_prerequisite(value)
      raise Onetime::ConfigError, restrict_to_error_message(value, unmet) if unmet

      @validate_restrict_to = value
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

    # Whether an SSO identity may auto-link to an account LOCATED purely by
    # email, for the given provider route name (#3836).
    #
    # This is the ONE sanctioned exception to the invariant that email may
    # LOCATE an account but only a demonstrated credential may BIND. It is an
    # explicit, opt-in operator declaration that the IdP is inside the trust
    # boundary — safe only when the operator controls both OTS and the IdP
    # (self-hosted single-tenant). It has NO effect on the multi-tenant
    # (tenant SsoConfig) surface; the callers gate that separately.
    #
    # Precedence:
    #   1. Per-provider ENV override (e.g. OIDC_TRUST_EMAIL_FOR_LINKING) when
    #      that var is present — 'true' enables, anything else disables.
    #   2. Deprecated global fallback (sso.trust_email_for_linking, from
    #      SSO_TRUST_EMAIL_FOR_LINKING) for the single-OIDC case and any
    #      provider without its own trust var set.
    #   3. Default: false.
    #
    # @param route_name [String, Symbol] the OmniAuth provider/route name
    # @return [Boolean]
    def trust_email_for_linking?(route_name)
      defn = provider_definition_for_route(route_name)

      # 1. Explicit per-provider override wins when the var is present.
      if defn && ENV.key?(defn[:trust_var])
        return ENV[defn[:trust_var]] == 'true'
      end

      # 2. Deprecated global / platform-wide fallback.
      return true if sso_trust_email_for_linking?

      # 3. Provider default (false), or false for unknown route names.
      defn ? !!defn[:trust_default] : false
    end

    # Whether the email-linking trust flag is EFFECTIVELY enabled for at least
    # one provider. Used by the boot guard to decide whether to warn about the
    # multi-tenant surface (a clean install with the flag off boots silently).
    #
    # Delegates to #trust_email_for_linking? per provider so the SAME precedence
    # applies: an explicit per-provider *_TRUST_EMAIL_FOR_LINKING wins over the
    # deprecated global SSO_TRUST_EMAIL_FOR_LINKING fallback. Consequently a
    # global `true` with EVERY provider explicitly opted out
    # (*_TRUST_EMAIL_FOR_LINKING=false) returns false — no provider is actually
    # trusted, so the guard stays silent rather than warning on a dead flag.
    #
    # @return [Boolean]
    def trust_email_for_linking_enabled?
      provider_definitions.any? do |defn|
        route_name = ENV.fetch(defn[:route_var], defn[:route_default])
        trust_email_for_linking?(route_name)
      end
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
    # Order follows provider_definitions (the registry), unless the operator
    # sets SSO_PROVIDER_ORDER — a comma/space-separated list of route names.
    # Listed providers come first in the given order; unlisted ones keep their
    # registry order after them, so a partial list is safe.
    def sso_providers
      return [] unless sso_enabled?

      providers = provider_definitions.filter_map do |defn|
        next unless defn[:required_vars].all? { |var| env_present?(var) }

        display = ENV.fetch(defn[:display_var], nil) || defn[:display_default]
        {
          'route_name' => ENV.fetch(defn[:route_var], defn[:route_default]),
          'display_name' => display,
        }
      end

      order_sso_providers(providers)
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
    # sovereign clouds and an OIDC issuer that differs from its authorization
    # endpoint. Tenant (per-domain) SSO issuers are NOT this method's job:
    # they are unknown at boot and reach the header per-request via
    # Onetime::Middleware::TenantCspExtras + #tenant_idp_origin (#4173).
    #
    # Returns a de-duplicated Array of origin strings (scheme://host[:port]),
    # or [] when nothing is configured. Side-effect free and safe to call at
    # router-build time (no auth-app boot required).
    def sso_form_action_origins
      provider_origins = active_provider_origins
      override_origins = override_form_action_origins

      # An override set with zero auto-derived provider origins is worth
      # surfacing — but it is not automatically a misconfiguration. Tenant SSO
      # no longer needs the override (tenant IdP origins arrive per-request
      # via Onetime::Middleware::TenantCspExtras, #4173), so this combination
      # now legitimately means sovereign-cloud or split-endpoint usage
      # (e.g. login.microsoftonline.us, or an OIDC authorization_endpoint on
      # a different origin than the issuer). Log it as context, not a smell.
      if provider_origins.empty? && !ENV.fetch('SSO_FORM_ACTION_ORIGINS', '').to_s.strip.empty?
        OT.lw '[auth_config] SSO_FORM_ACTION_ORIGINS is widening CSP form-action with ' \
              'no active platform SSO provider origins — expected only for sovereign-cloud ' \
              'or split-endpoint IdPs (tenant SSO origins are added per-request and do not ' \
              'need this override)'
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
      remove_instance_variable(:@validate_restrict_to) if defined?(@validate_restrict_to)
      load_config
      self
    end

    # Provider definitions for sso_providers, email-linking trust, and CSP
    # form-action origins. The data lives in Onetime::SsoProvider::Registry —
    # the SAME registry the auth app's boot-time strategy registration
    # consumes — so serializer gating, CSP origins, and registered strategies
    # can never drift apart. Each entry defines the env vars that gate the
    # provider and where to read its route/display names; see the registry
    # for the full field reference.
    #
    # trust_var / trust_default gate the #3836 email-linking escape hatch:
    # an explicit, per-provider operator declaration that the IdP is inside
    # the trust boundary, so an SSO identity may auto-link to an account
    # LOCATED by email. See #trust_email_for_linking?.
    #
    # The one dynamic overlay: OIDC's display default honors the operator's
    # legacy sso_display_name before falling back to the registry's 'SSO'.
    #
    # Public: the auth app's boot registration reads it (via
    # display_default_for) so its logs share the serializer's view.
    def provider_definitions
      SsoProvider::Registry::DEFINITIONS.map do |defn|
        next defn unless defn[:key] == :oidc

        legacy_display = sso_display_name
        legacy_display ? defn.merge(display_default: legacy_display) : defn
      end
    end

    # The CSP form-action origin for a TENANT's IdP (#4173) — the per-request
    # complement to the boot-time #sso_form_action_origins. Tenant SSO issuers
    # live in per-domain CustomDomain::SsoConfig records, so they cannot be
    # derived at boot; Onetime::Middleware::TenantCspExtras calls this per
    # request and feeds the result through otto's request-scoped CSP extras
    # channel (env['otto.csp.extra_directives'], delano/otto#243).
    #
    # The issuer is tenant-supplied and therefore attacker-influenced, so
    # #origin_from_url is the mandatory funnel: it strips the path, accepts
    # only http(s), rejects CSP-hostile hosts, omits default ports, and
    # returns nil on garbage — never raises. Entra reuses the registry's
    # static commercial-cloud origin (the tenant strategy pins that cloud:
    # SsoConfig#build_entra_id_options passes no authority option); sovereign
    # clouds remain SSO_FORM_ACTION_ORIGINS territory.
    #
    # Caveat (same as the platform OIDC derivation): OIDC discovery may place
    # authorization_endpoint on a DIFFERENT origin than the issuer, so the
    # issuer origin is best-effort and SSO_FORM_ACTION_ORIGINS stays the
    # escape hatch for split-endpoint topologies.
    #
    # @param sso_config [Onetime::CustomDomain::SsoConfig] the tenant's record
    # @return [String, nil] scheme://host[:port], or nil when the provider
    #   type is unknown or the issuer does not resolve to a clean origin
    def tenant_idp_origin(sso_config)
      case sso_config&.provider_type
      when 'oidc'
        origin_from_url(sso_config.issuer)
      when 'entra_id'
        SsoProvider::Registry.fetch(:entra)[:idp_origin]
      end
    end

    private

    # The restriction as CONFIGURED, before any validation: the stripped
    # full.restrict_to value, or 'sso' via the legacy sso.sso_only fallback.
    # Returns '' when nothing is configured. May be an unrecognised value —
    # #validate_restrict_to! is what rejects those.
    def configured_restrict_to
      value = full['restrict_to'].to_s.strip
      # Legacy fallback: configs that still use sso.sso_only instead of restrict_to
      value = 'sso' if value.empty? && legacy_sso_only?
      value
    end

    # Which config key the restriction came from, for operator-facing errors.
    def restrict_to_source
      full['restrict_to'].to_s.strip.empty? ? 'full.sso.sso_only (AUTH_SSO_ONLY)' : 'full.restrict_to'
    end

    # The unmet prerequisite for a restriction value, as an operator-facing
    # phrase, or nil when the method is available.
    #
    # 'password' is deliberately absent: password authentication has no
    # feature flag in full mode — Rodauth's login/password features are
    # always loaded — so there is no prerequisite that could fail. If a
    # password-disable switch is ever introduced, it belongs here.
    def restrict_to_unmet_prerequisite(value)
      case value
      when 'sso'
        return 'SSO is disabled (full.features.sso / AUTH_SSO_ENABLED)' unless sso_enabled?
        if sso_providers.empty?
          return 'SSO is enabled but no provider is configured (no provider has its ' \
                 'required env vars set, e.g. OIDC_ISSUER + OIDC_CLIENT_ID)'
        end
      when 'email_auth'
        return 'email auth is disabled (full.features.email_auth / AUTH_EMAIL_AUTH_ENABLED)' unless email_auth_enabled?
      when 'webauthn'
        return 'WebAuthn is disabled (full.features.webauthn / AUTH_WEBAUTHN_ENABLED)' unless webauthn_enabled?
      end

      nil
    end

    # Operator-facing fatal message for an unusable restriction. `unmet` is
    # nil when the value itself is not a valid restriction.
    def restrict_to_error_message(value, unmet)
      reason = unmet || "#{value.inspect} is not a valid restriction " \
                        "(expected one of: #{RESTRICT_TO_VALUES.join(', ')})"

      <<~MSG.strip
        Authentication is restricted to #{value.inspect} (#{restrict_to_source}) but #{reason}.

        Refusing to boot: continuing would silently show every enabled sign-in
        method, re-exposing exactly the methods this setting restricts away.

        To fix this issue:
        1. Enable the prerequisite for #{value.inspect}, or
        2. Change #{restrict_to_source} to an available method
           (one of: #{RESTRICT_TO_VALUES.join(', ')}), or
        3. Clear it to show all enabled authentication methods.
      MSG
    end

    # Nil for a nil/blank/whitespace-only value, the value otherwise.
    # Lets `presence(x) || default` behave the way `x || default` is
    # usually intended when x originates from an environment variable.
    def presence(value)
      return nil if value.nil?

      str = value.to_s.strip
      str.empty? ? nil : value
    end

    # Whether the legacy sso.sso_only flag is set in config.
    # Used as a fallback by #restrict_to for configs that predate
    # the restrict_to key.
    def legacy_sso_only?
      sso_config['sso_only'] == true
    end

    # Global (deprecated single-OIDC) email-linking trust flag.
    # Read from sso.trust_email_for_linking (rendered from
    # SSO_TRUST_EMAIL_FOR_LINKING in auth.defaults.yaml).
    def sso_trust_email_for_linking?
      sso_config['trust_email_for_linking'] == true
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

    # Apply the SSO_PROVIDER_ORDER override (comma/space-separated route
    # names) to the serializer's provider list. Stable: providers not listed
    # keep their relative registry order, after the listed ones.
    def order_sso_providers(providers)
      order = ENV.fetch('SSO_PROVIDER_ORDER', '').split(/[,\s]+/).reject(&:empty?)
      return providers if order.empty?

      providers.sort_by.with_index do |provider, index|
        [order.index(provider['route_name']) || order.length, index]
      end
    end

    # Reverse-map a route/provider name to its provider definition.
    #
    # Keys on the ROUTE NAME (the value returned by omniauth_provider and
    # stored in account_identities.provider), NOT the env prefix or the
    # provider_type. A provider's route name is ENV[route_var] when set,
    # otherwise route_default (e.g. 'oidc', 'entra', 'google', 'github').
    #
    # @param route_name [String] the OmniAuth provider/route name
    # @return [Hash, nil] the matching provider definition, or nil
    def provider_definition_for_route(route_name)
      route_name = route_name.to_s
      return nil if route_name.empty?

      provider_definitions.find do |defn|
        ENV.fetch(defn[:route_var], defn[:route_default]) == route_name
      end
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
