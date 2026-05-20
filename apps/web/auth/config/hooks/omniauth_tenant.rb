# apps/web/auth/config/hooks/omniauth_tenant.rb
#
# frozen_string_literal: true

#
# Runtime SSO credential injection for multi-tenant configurations.
#
# This hook resolves tenant-specific SSO credentials from the Host header
# and injects them into the OmniAuth strategy before authentication begins.
# It enables organizations to configure their own IdP connections without
# requiring platform environment variables.
#
# Flow (domain-based resolution):
#   1. Host header -> CustomDomain lookup
#   2. CustomDomain.identifier -> CustomDomain::SsoConfig
#   3. SSO config -> omniauth strategy.options injection
#
# Each domain has its own SSO configuration, enabling multi-IdP setups where
# different domains owned by the same organization use different identity providers.
#
# Security Model:
#   - Tenant context (domain_id) stored in session during request phase
#   - Callback validates tenant context matches (prevents redirect attacks)
#   - Missing tenant config can either fall back to platform credentials
#     or reject the request based on `allow_platform_fallback_for_tenants`
#
# See: docs/authentication/omniauth-sso.md (full configuration guide)
# See: lib/onetime/models/custom_domain/sso_config.rb (per-domain SSO config)
#

module Auth::Config::Hooks
  module OmniAuthTenant
    # Module reference for calling helper methods from within Rodauth blocks
    HELPERS = self

    # Map CustomDomain::SsoConfig provider_type symbols to OmniAuth strategy class names.
    # Used to validate that credentials are being injected into the correct strategy.
    STRATEGY_CLASS_MAP = {
      openid_connect: %w[OmniAuth::Strategies::OpenIDConnect],
      entra_id: %w[OmniAuth::Strategies::EntraId OmniAuth::Strategies::AzureActivedirectoryV2],
      google_oauth2: %w[OmniAuth::Strategies::GoogleOauth2],
      github: %w[OmniAuth::Strategies::GitHub],
    }.freeze

    def self.configure(auth)
      # ========================================================================
      # HOOK: OmniAuth Setup - Runtime Credential Injection
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires BEFORE the OmniAuth request phase, allowing us to
      # inject tenant-specific credentials into the strategy. The strategy
      # has already been selected based on the URL path (e.g., /auth/sso/oidc).
      #
      # NOTE: OmniAuth strategies are registered at boot with platform defaults.
      # This hook overrides those defaults at runtime for tenant-specific flows.
      #
      auth.omniauth_setup do
        host = request.host

        Auth::Logging.log_auth_event(
          :omniauth_tenant_resolution_start,
          level: :debug,
          host: host,
          path: request.path,
          ip: request.ip,
        )

        # Attempt to resolve tenant from custom domain
        custom_domain = HELPERS.resolve_custom_domain(host)

        unless custom_domain
          # Check if this is the platform's canonical domain.
          # Canonical domain requests are platform-level, not tenant requests,
          # so tenant fallback policy should not apply.
          if HELPERS.canonical_domain?(host)
            Auth::Logging.log_auth_event(
              :omniauth_canonical_domain_request,
              level: :debug,
              host: host,
            )
            next # Continue with platform defaults
          end

          # Non-canonical domain with no custom domain mapping - apply tenant policy
          HELPERS.handle_missing_tenant_config(host, self)
          next # Continue with platform defaults (if allowed)
        end

        # Look up domain-specific SSO configuration
        sso_config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(custom_domain.identifier)

        unless sso_config&.enabled?
          Auth::Logging.log_auth_event(
            :omniauth_tenant_sso_not_enabled,
            level: :info,
            host: host,
            domain_id: custom_domain.identifier,
          )

          # Check if we should fall back to platform credentials
          HELPERS.handle_missing_tenant_config(host, self)
          next # Continue with platform defaults (if allowed)
        end

        # Store tenant context in session for callback validation
        # This prevents an attacker from initiating auth on domain A
        # then redirecting callback to domain B.
        session[:omniauth_tenant_domain_id] = custom_domain.identifier
        session[:omniauth_tenant_host]      = host

        Auth::Logging.log_auth_event(
          :omniauth_tenant_credentials_injecting,
          level: :info,
          host: host,
          domain_id: custom_domain.identifier,
          provider_type: sso_config.provider_type,
        )

        # Inject tenant-specific credentials into strategy
        HELPERS.inject_tenant_credentials(sso_config, request, self)
      end

      # ========================================================================
      # HOOK: Before OmniAuth Callback - Tenant Context Validation
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires at the very start of callback processing.
      # We validate that the callback is arriving at the same tenant that
      # initiated the auth request. This prevents cross-tenant redirect attacks.
      #
      # The before_omniauth_callback_route hook (in omniauth.rb) runs BEFORE this
      # one (it is registered first in config.rb). This hook validates tenants.
      #
      auth.before_omniauth_callback_route do
        expected_domain_id = session.delete(:omniauth_tenant_domain_id)
        expected_host      = session.delete(:omniauth_tenant_host)

        # If no tenant context was stored, this was a platform-level auth
        # (no tenant credentials were injected). Allow it to proceed.
        next unless expected_domain_id

        # Resolve current request's tenant context
        current_domain = HELPERS.resolve_custom_domain(request.host)

        # Validate tenant context matches - domain_id must match exactly
        domain_mismatch = current_domain&.identifier != expected_domain_id

        if domain_mismatch
          Auth::Logging.log_auth_event(
            :omniauth_tenant_mismatch,
            level: :warn,
            expected_domain_id: expected_domain_id,
            expected_host: expected_host,
            actual_host: request.host,
            actual_domain_id: current_domain&.identifier,
            ip: request.ip,
          )

          throw_error_status(403, 'tenant_mismatch', 'Authentication context mismatch')
        end

        Auth::Logging.log_auth_event(
          :omniauth_tenant_callback_validated,
          level: :debug,
          domain_id: expected_domain_id,
          host: request.host,
        )
      end
    end

    # ==========================================================================
    # Helper Methods
    # ==========================================================================
    #
    # These are module methods called via HELPERS constant from Rodauth blocks.
    # They cannot access Rodauth instance methods directly - pass needed objects.
    #

    # Resolve custom domain from hostname.
    # Returns nil if no custom domain mapping exists.
    #
    # @param host [String] Request hostname
    # @return [Onetime::CustomDomain, nil]
    def self.resolve_custom_domain(host)
      return nil if host.to_s.empty?

      Onetime::CustomDomain.load_by_display_domain(host)
    rescue Redis::BaseError => ex
      Auth::Logging.log_auth_event(
        :omniauth_tenant_resolution_error,
        level: :error,
        host: host,
        error: ex.message,
      )
      nil
    end

    # Check if host is the platform's canonical domain.
    #
    # Platform-level requests (on the canonical domain) should not be subject
    # to tenant fallback policy - they are not tenant requests at all.
    #
    # @param host [String] Request hostname
    # @return [Boolean] true if host matches canonical domain
    def self.canonical_domain?(host)
      return false if host.to_s.empty?

      canonical = Onetime::Middleware::DomainStrategy.canonical_domain
      return false if canonical.nil?

      # Normalize comparison (case-insensitive)
      host.to_s.downcase == canonical.to_s.downcase
    end

    # Handle requests where no tenant SSO config is available.
    # Either allows fallback to platform credentials or rejects.
    #
    # Configured via auth_config.allow_platform_fallback_for_tenants?
    #
    # @param host [String] Request hostname for logging
    # @param rodauth [Rodauth] Rodauth instance (for throw_error_status)
    # @raise [Rodauth::Error] if fallback not allowed
    def self.handle_missing_tenant_config(host, rodauth)
      if Onetime.auth_config.allow_platform_fallback_for_tenants?
        Auth::Logging.log_auth_event(
          :omniauth_tenant_fallback_to_platform,
          level: :debug,
          host: host,
        )
        return # Continue with platform defaults
      end

      Auth::Logging.log_auth_event(
        :omniauth_tenant_no_config,
        level: :warn,
        host: host,
      )

      rodauth.throw_error_status(403, 'sso_not_configured', 'SSO not configured for this domain')
    end

    # Inject tenant credentials into the OmniAuth strategy.
    #
    # Accesses the strategy from request.env['omniauth.strategy'] and
    # merges in the tenant's OAuth configuration.
    #
    # @param sso_config [Onetime::CustomDomain::SsoConfig] The SSO config
    # @param request [Rack::Request] The current request
    # @param rodauth [Rodauth] Rodauth instance (for throw_error_status)
    # @raise [Rodauth::Error] if strategy type doesn't match configuration
    def self.inject_tenant_credentials(sso_config, request, rodauth)
      strategy = request.env['omniauth.strategy']
      return unless strategy

      options = sso_config.to_omniauth_options

      # Extract the strategy-specific options (excluding :strategy and :name keys
      # which are used for provider registration, not runtime configuration)
      expected_strategy = options.delete(:strategy)
      _strategy_name    = options.delete(:name)

      # Validate strategy type matches configuration to prevent credential injection
      # into wrong strategy (e.g., Google credentials into OIDC strategy)
      unless strategy_matches?(strategy, expected_strategy)
        Auth::Logging.log_auth_event(
          :omniauth_strategy_mismatch,
          level: :warn,
          expected_strategy: expected_strategy,
          actual_strategy: strategy.class.name,
          domain_id: sso_config.domain_id,
          provider_type: sso_config.provider_type,
        )
        rodauth.throw_error_status(
          400,
          'provider_mismatch',
          "SSO provider mismatch: tenant configured #{sso_config.provider_type}, but request is for #{strategy.class.name}",
        )
      end

      Auth::Logging.log_auth_event(
        :omniauth_strategy_options_merging,
        level: :debug,
        strategy_class: strategy.class.name,
        options_keys: options.keys.join(','),
      )

      # Merge tenant options into strategy
      # This modifies the strategy's options hash in place
      merge_strategy_options(strategy, options)

      # For OIDC strategies, clear memoized discovery data
      # The strategy may have cached the discovery document and client
      # from boot-time configuration; we need fresh instances.
      clear_oidc_memoization(strategy)
    end

    # Check if the active OmniAuth strategy matches the expected type.
    #
    # @param strategy [OmniAuth::Strategy] The active strategy instance
    # @param expected_type [Symbol] Expected strategy type from CustomDomain::SsoConfig
    # @return [Boolean] true if strategy class matches expected type
    def self.strategy_matches?(strategy, expected_type)
      return false unless strategy && expected_type

      expected_classes = STRATEGY_CLASS_MAP[expected_type]
      return false unless expected_classes

      expected_classes.include?(strategy.class.name)
    end

    # Merge options into the strategy, handling nested client_options.
    #
    # @param strategy [OmniAuth::Strategy] The active strategy
    # @param options [Hash] Options to merge
    def self.merge_strategy_options(strategy, options)
      options.each do |key, value|
        if key == :client_options && value.is_a?(Hash)
          # Deep merge client_options for OIDC
          strategy.options[:client_options] ||= {}
          value.each do |client_key, client_value|
            strategy.options[:client_options][client_key] = client_value
          end
        else
          strategy.options[key] = value
        end
      end
    end

    # Clear memoized OIDC discovery data on the strategy.
    #
    # OmniAuth::Strategies::OpenIDConnect memoizes @config (discovery doc)
    # and @client (OpenIDConnect::Client instance). When we inject new
    # credentials at runtime, these cached objects have stale data.
    #
    # @param strategy [OmniAuth::Strategy] The active strategy
    def self.clear_oidc_memoization(strategy)
      # Only clear for OIDC-based strategies
      return unless strategy.respond_to?(:options) &&
                    strategy.options[:discovery] == true

      # Clear memoized instance variables if they exist
      # This forces the strategy to re-fetch discovery and re-create client
      strategy.instance_variable_set(:@config, nil) if strategy.instance_variable_defined?(:@config)
      strategy.instance_variable_set(:@client, nil) if strategy.instance_variable_defined?(:@client)

      Auth::Logging.log_auth_event(
        :omniauth_oidc_memoization_cleared,
        level: :debug,
        strategy_class: strategy.class.name,
      )
    end
  end
end
