# apps/web/core/views/serializers/config_serializer.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signin_config'
require 'onetime/models/custom_domain/sso_config'
require 'onetime/models/custom_domain'
require 'onetime/tenant_sso_resolution'

module Core
  module Views
    # Serializes application configuration for the frontend
    #
    # Responsible for transforming server-side configuration settings into
    # a consistent format that can be safely exposed to the frontend.
    #
    # SSO Provider Resolution:
    # The serializer returns domain-aware SSO providers based on request context:
    #   1. If request is from a custom domain with CustomDomain::SsoConfig -> tenant's provider
    #   2. If tenant has no config or is disabled -> platform fallback (if allowed)
    #   3. If fallback disallowed -> empty providers array
    #
    # Resolution Flow:
    #   view_vars['display_domain'] -> CustomDomain.from_display_domain -> CustomDomain::SsoConfig
    #
    module ConfigSerializer
      # Sentinel returned by resolve_domain_id when a datastore read fails.
      # Callers must check for this and render the narrowest surface rather
      # than treating it as "no tenant config" (#4157). Owned by
      # Onetime::TenantSsoResolution, which performs the read.
      DOMAIN_READ_FAILED = Onetime::TenantSsoResolution::DOMAIN_READ_FAILED

      # Serializes configuration data from view variables
      #
      # Transforms server configuration including site settings, feature flags,
      # and environment variables into frontend-safe configuration.
      #
      # @param view_vars [Hash] The view variables containing site configuration
      # @return [Hash] Serialized configuration data
      def self.serialize(view_vars)
        output = output_template

        # NOTE: The keys available in view_vars are defined in initialize_view_vars
        site        = view_vars['site'] || {}
        features    = view_vars['features'] || {}
        development = view_vars['development']
        diagnostics = view_vars['diagnostics']

        output['ui']             = site.dig('interface', 'ui')
        output['api']            = {
          'enabled' => site.dig('interface', 'api', 'enabled') != false,
          'guest_routes' => site.dig('interface', 'api', 'guest_routes') || {},
        }
        output['authentication'] = site.fetch('authentication', nil)
        output['homepage_mode']  = view_vars['homepage_mode']
        output['secret_options'] = build_secret_options(site)
        output['site_host']      = site['host']
        output['support_host']   = site.dig('support', 'host')
        regions                  = features.fetch('regions', {})
        domains                  = features.fetch('domains', {})

        # Only send the regions config when the feature is enabled.
        # Transform jurisdictions to send identifier + i18n key only (no domain data).
        output['regions_enabled'] = regions.fetch('enabled', false)
        output['regions']         = transform_regions(regions) if output['regions_enabled']

        # Only send the allowlisted domains fields when the feature is enabled.
        # The raw config subtree also carries the Approximated credentials
        # (approximated.api_key et al.) and the internal ACME listener — the
        # DNS proxy targets a domain owner needs are served by the
        # authenticated domains API via DomainValidation::Features.safe_dump.
        output['domains_enabled'] = domains.fetch('enabled', false)
        output['domains']         = transform_domains(domains) if output['domains_enabled']

        # Link to the pricing page can be seen regardless of authentication status
        output['billing_enabled'] = OT.billing_config.enabled?
        output['checkout_host']   = OT.billing_config.checkout_host.to_s

        output['frontend_development'] = development['enabled'] || false
        output['frontend_host']        = development['frontend_host'] || ''

        # Branding config for frontend stores. brand_primary_color is nil
        # when BRAND_PRIMARY_COLOR is unset — the frontend fallback chain
        # resolves the default (#3381).
        output['brand_primary_color']         = view_vars['brand_primary_color']
        output['brand_product_name']          = view_vars['brand_product_name']
        output['brand_product_domain']        = view_vars['brand_product_domain']
        output['brand_support_email']         = view_vars['brand_support_email']
        output['brand_corner_style']          = view_vars['brand_corner_style']
        output['brand_font_family']           = view_vars['brand_font_family']
        output['brand_button_text_light']     = view_vars['brand_button_text_light']
        output['brand_logo_url']              = view_vars['brand_logo_url']
        output['brand_logo_dark_url']         = view_vars['brand_logo_dark_url']
        output['brand_logo_alt']              = view_vars['brand_logo_alt']
        output['brand_favicon_url']           = view_vars['brand_favicon_url']
        output['support_email']               = view_vars['support_email']
        output['docs_host']                   = view_vars['docs_host']

        # Pass development config to frontend (includes domain_context_enabled)
        output['development'] = {
          'enabled' => development['enabled'] || false,
          'domain_context_enabled' => development['domain_context_enabled'] || false,
        }

        sentry                = diagnostics.fetch('sentry', {})
        output['d9s_enabled'] = Onetime.d9s_enabled
        Onetime.with_diagnostics do
          defaults = sentry.fetch('defaults', {})
          frontend = sentry.fetch('frontend', {})

          output['diagnostics'] = {
            'sentry' => {
              'dsn' => frontend.fetch('dsn', ''),
              'trackComponents' => frontend.fetch('trackComponents', true),
              'sampleRate' => defaults.fetch('sampleRate', 1.0).to_f,
              'maxBreadcrumbs' => defaults.fetch('maxBreadcrumbs', 5).to_i,
              'logErrors' => defaults.fetch('logErrors', true),
              'environment' => OT.env,
              'release' => OT::VERSION.get_build_info,
            },
          }
        end

        # Feature flags for authentication methods
        # Only available in full mode (Rodauth)
        output['features'] = build_feature_flags(view_vars)

        output
      end

      class << self
        # Site secret_options with the anonymous TTL ceiling replaced by the
        # value the server actually enforces.
        #
        # secret_options already carries the raw ttl_max_anonymous config value;
        # the merge overwrites it with the resolved ceiling, so the frontend
        # never sees a configured number that the free-tier limit would have
        # lowered underneath it.
        #
        # @param site [Hash] site config section
        # @return [Hash, nil] secret_options for the bootstrap payload
        def build_secret_options(site)
          secret_options = site['secret_options']
          return secret_options unless secret_options.is_a?(Hash)

          secret_options.merge('ttl_max_anonymous' => anonymous_ttl_ceiling)
        end

        # Anonymous TTL ceiling for the duration dropdown (2026-07-29 API
        # audit, item 4).
        #
        # V2 silently clamps an anonymous secret's TTL (V2::Logic::Secrets::
        # BaseSecretAction#anonymous_max_ttl). Publishing the same number lets
        # the web UI (src/shared/composables/usePrivacyOptions.ts) drop
        # durations the server would quietly reduce, instead of offering a
        # duration the caller will never get.
        #
        # Mirrors that method's ladder. The configured ceiling
        # (site.secret_options.ttl_max_anonymous, default 7 days) is read on
        # every deployment, billing enabled or not, and has no fail-open case,
        # so this key is always emitted. The free-tier limit can only lower it
        # further, and only when billing is enabled. The third term server-side
        # is the config ttl_options max; here it is implicit, since the dropdown
        # is built from ttl_options in the first place.
        #
        # @return [Integer] Ceiling in seconds
        def anonymous_ttl_ceiling
          [
            Onetime::Models::Features::WithEntitlements.configured_anonymous_max_ttl,
            free_tier_ttl_override,
          ].compact.min
        end

        # Free-tier secret_lifetime limit, when it applies.
        #
        # Consulted only with billing enabled, and only when positive — with
        # billing off there is no free tier to bound the anonymous grant
        # against. The rescue drops only this term; the configured ceiling still
        # stands, because a bootstrap read must never take the page down over a
        # billing-config fault.
        #
        # @return [Integer, nil] Limit in seconds, or nil when not applicable
        def free_tier_ttl_override
          return nil unless OT.billing_config.enabled?

          free_tier_max = Onetime::Organization.free_tier_limits['secret_lifetime.max'].to_i
          free_tier_max.positive? ? free_tier_max : nil
        rescue StandardError => ex
          OT.le "[ConfigSerializer] free-tier TTL limit unavailable (#{ex.class}: #{ex.message}); " \
                'anonymous duration ceiling falls back to the configured value'
          nil
        end

        # Provides the base template for configuration serializer output
        #
        # @return [Hash] Template with all possible configuration output fields
        def output_template
          {
            'api' => nil,
            'authentication' => nil,
            'brand_primary_color' => nil,
            'brand_product_name' => nil,
            'brand_product_domain' => nil,
            'brand_support_email' => nil,
            'brand_corner_style' => nil,
            'brand_font_family' => nil,
            'brand_button_text_light' => nil,
            'brand_logo_url' => nil,
            'brand_logo_dark_url' => nil,
            'brand_logo_alt' => nil,
            'brand_favicon_url' => nil,
            'd9s_enabled' => nil,
            'development' => nil,
            'diagnostics' => nil,
            'docs_host' => nil,
            'domains' => nil,
            'domains_enabled' => nil,
            'features' => nil,
            'frontend_development' => nil,
            'frontend_host' => nil,
            'homepage_mode' => nil,
            'billing_enabled' => nil,
            'checkout_host' => nil,
            'regions' => nil,
            'regions_enabled' => nil,
            'secret_options' => nil,
            'site_host' => nil,
            'support_email' => nil,
            'support_host' => nil,
            'ui' => nil,
          }
        end

        # Build feature flags for authentication methods
        #
        # Feature flags indicate which authentication methods are available
        # based on the current authentication mode (simple vs full).
        # Uses AuthConfig methods which already check full_enabled? internally.
        #
        # @param view_vars [Hash] View variables with request context
        # @return [Hash] Feature flags for frontend consumption
        def build_feature_flags(view_vars)
          features               = view_vars['features'] || {}
          restrict_to_resolution = restrict_to_resolution(view_vars)

          {
            'signin' => resolve_signin(view_vars),
            'lockout' => Onetime.auth_config.lockout_enabled?,
            'password_requirements' => Onetime.auth_config.password_requirements_enabled?,
            'active_sessions' => Onetime.auth_config.active_sessions_enabled?,
            'remember_me' => Onetime.auth_config.remember_me_enabled?,
            'mfa' => Onetime.auth_config.mfa_enabled?,
            'email_auth' => resolve_email_auth(view_vars),
            'webauthn' => Onetime.auth_config.webauthn_enabled?,
            'sso' => build_sso_config(view_vars),
            # Keep the scalar for existing consumers, and carry the resolver's
            # full wire form so :unavailable is not widened to standard mode.
            'restrict_to' => restrict_to_resolution.unavailable? ? nil : restrict_to_resolution.restrict_to,
            'effective_restrict_to' => restrict_to_resolution.to_wire.transform_keys(&:to_s),
            'organizations' => {
              'enabled' => features.dig('organizations', 'enabled') || false,
              'sso_enabled' => features.dig('organizations', 'sso_enabled') || false,
              'custom_mail_enabled' => features.dig('organizations', 'custom_mail_enabled') || false,
              # Whether domain owners can configure per-domain incoming is
              # governed solely by ORGS_INCOMING_SECRETS_ENABLED. The
              # install-wide features.incoming.enabled flag gates the CANONICAL
              # domain's incoming only; ANDing it here would hide the per-domain
              # config UI on a flag-off install, so an entitled custom domain
              # could never reach IncomingConfig.ready?. Same canonical/custom
              # split as RecipientResolver / HomepageConfig#incoming_available?.
              'incoming_secrets_enabled' => features.dig('organizations', 'incoming_secrets_enabled') || false,
              # Default-true contract: only an explicit false disables — a
              # missing key (older config file) must still read as enabled.
              # Compare on the string form so a hand-edited config that yields
              # 'false' (quoted/ERB-stringified) still disables the flag.
              'audit_logs_enabled' => features.dig('organizations', 'audit_logs_enabled').to_s != 'false',
            },
            'secret_activity' => {
              # Same default-true contract as audit_logs_enabled above: only
              # an explicit false pauses collection; compare on the string
              # form for quoted/ERB-stringified 'false'. This is the
              # data-existence axis — audit_logs_enabled is UI exposure.
              'collect_enabled' => features.dig('secret_activity', 'collect').to_s != 'false',
              'max_events' => resolve_secret_activity_max_events(features),
              # Country column on the org Secret Activity trail. DEFAULT-OFF
              # (opt-in) — the inverse polarity of the flags above — gated
              # pending counsel review of org-tier geo exposure (#3989; ADR-021
              # Decision 4). Only an explicit true enables it.
              'geo_country_enabled' => features.dig('secret_activity', 'geo_country_enabled').to_s == 'true',
            },
          }
        end

        # The retention cap actually enforced on the org trail: mirrors the
        # boot-time coercion (ConfigureSecretActivity) and clamp
        # (SecretActivity.configure!) so the UI never advertises a cap the
        # backend ignored.
        def resolve_secret_activity_max_events(features)
          feature = Onetime::Organization::Features::SecretActivity
          max     = Integer(features.dig('secret_activity', 'max_events'))
          [max, feature::MIN_MAX_EVENTS].max
        rescue ArgumentError, TypeError
          Onetime::Organization::Features::SecretActivity::DEFAULT_MAX_EVENTS
        end

        # Wire value of features.restrict_to for the current request context.
        #
        # DISPLAY CONSUMER ONLY (ADR-034#resolution-is-model-owned): resolution itself belongs to
        # SigninConfig.resolve_restrict_to — precedence between global and
        # domain, and the fail-closed degradation of a domain restriction whose
        # method cannot be honored, are decided there and re-derived nowhere.
        # This method's whole job is to gather the two inputs and flatten the
        # result onto the bootstrap payload.
        #
        # features.restrict_to remains the backwards-compatible string-or-null
        # projection. build_feature_flags also emits effective_restrict_to so
        # display consumers retain the resolver's explicit :unavailable state.
        #
        # @param view_vars [Hash] View variables with request context
        # @return [String, nil] the single permitted method, or nil for standard mode
        def resolve_restrict_to(view_vars)
          resolution = restrict_to_resolution(view_vars)
          return nil if resolution.unavailable?

          resolution.restrict_to
        end

        # Resolver output for the current request context.
        #
        # @param view_vars [Hash] View variables with request context
        # @return [Onetime::CustomDomain::SigninConfig::RestrictToResolution]
        def restrict_to_resolution(view_vars)
          domain_id = resolve_domain_id(view_vars)

          # Tri-state handling (#4157): failed read → unavailable (no auth methods).
          if domain_id == DOMAIN_READ_FAILED
            return Onetime::CustomDomain::SigninConfig::RestrictToResolution.new(
              restrict_to: nil,
              state: :unavailable,
              source: :domain_read_failed,
            )
          end

          signin_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id) if domain_id
          inherited     = effective_global_restrict_to(view_vars, signin_config, domain_id)

          Onetime::CustomDomain::SigninConfig.resolve_restrict_to(
            inherited.value,
            signin_config,
            # Post-boot availability of the global restriction (ADR-034#degradation-is-fail-closed),
            # asked through the SHARED gatherer so the page cannot answer it
            # differently from the route gate. It briefly did: with only
            # global_restriction_available? here, this page reported
            # `restricted/password` on a custom host with no enabled
            # SigninConfig under a global password restriction, while the gate
            # narrowed through the custom-host capabilities (password defaults
            # OFF there), resolved :unavailable, and 404'd the very routes this
            # page's form posts to (#4139).
            #
            # #4165: pass pin_established so the availability check trusts the
            # SSO pin's own proof instead of re-consulting AuthConfig.
            available: Onetime::CustomDomain::SigninConfig.restriction_available_for_request?(
              inherited.value,
              signin_config,
              domain_id: domain_id,
              custom_host: tenant_domain?(view_vars),
              already_established: inherited.pin_established,
            ),
          )
        end

        # The restriction this REQUEST HOST inherits when no enabled per-domain
        # config speaks — the `global` input to the resolver.
        #
        # The pin POLICY is SigninConfig.inherited_restrict_to (see it for why
        # an SSO-only custom host inherits 'sso' and why the pin may only apply
        # when no enabled domain config speaks). It is shared with the runtime
        # gate (Auth::RestrictTo.global_restrict_to) and the settings API
        # (DomainsAPI signin_config details), so the page cannot inherit a
        # different restriction from the routes it posts to
        # (ADR-034#resolution-is-model-owned). All that is left here is the
        # display side's own request facts: the tenant-host classification and
        # the #4157 read-failure tri-state.
        #
        # @param view_vars [Hash] View variables with request context
        # @param signin_config [Onetime::CustomDomain::SigninConfig, nil]
        # @param domain_id [String, nil, :domain_read_failed] already-resolved CustomDomain objid
        # @return [Onetime::CustomDomain::SigninConfig::InheritedRestriction]
        def effective_global_restrict_to(view_vars, signin_config = nil, domain_id = nil)
          # Tri-state handling (#4157): if domain_id is DOMAIN_READ_FAILED, the
          # caller should have already short-circuited. If we reach here anyway,
          # don't attempt the SSO pin — fall through to global.
          custom_host = tenant_domain?(view_vars) && domain_id != DOMAIN_READ_FAILED

          if custom_host && !signin_config&.enabled?
            domain_id ||= resolve_domain_id(view_vars)
            # Defensive: if the fallback read also failed, skip the SSO pin.
            custom_host = domain_id != DOMAIN_READ_FAILED
          end

          Onetime::CustomDomain::SigninConfig.inherited_restrict_to(
            signin_config,
            domain_id: custom_host ? domain_id : nil,
            custom_host: custom_host,
          )
        end

        # Resolve sign-in availability for the current request context.
        #
        # AND semantics (mirrors resolve_email_auth): a domain may DISABLE
        # sign-in entirely but can never enable it when sign-in is off
        # globally (AUTH_ENABLED + AUTH_SIGNIN). The domain override only
        # ever narrows the global capability.
        #
        # This is the DISPLAY gate: features.signin in the bootstrap lets
        # the public /signin page render a friendly "not available" notice
        # instead of the auth form. The runtime POST gate lives in
        # Core::Controllers::Base#signin_enabled? and resolves through the
        # same custom-domain-aware logic, so the rendered page and the POST
        # handler cannot disagree. Resolution semantics: ADR-024.
        #
        # Custom domains default OFF (opt-in): a custom domain that has not
        # enabled a SigninConfig shows the "not available" notice instead of
        # the password/email form — matching the runtime route gate and the
        # branded masthead. The one exception is SSO: SSO is an independent,
        # explicitly-configured sign-in path (SsoConfig), so when tenant/
        # platform SSO is active we keep the page available so its provider
        # buttons still render even without a SigninConfig. An *enabled*
        # SigninConfig falls through to the shared resolver, preserving the
        # per-domain explicit-disable semantics (#3415), including hiding SSO
        # when the owner set signin_enabled=false. Canonical / subdomain
        # requests follow the global default (ADR-024 invariant #2).
        #
        # @param view_vars [Hash] View variables with request context
        # @return [Boolean] true if sign-in is available
        def resolve_signin(view_vars)
          auth_settings = (view_vars['site'] || {})['authentication'] || {}
          global        = auth_settings['enabled'] && auth_settings['signin']

          domain_id = resolve_domain_id(view_vars)

          # Tri-state handling (#4157): a failed read is not "no tenant config."
          # Render the narrowest surface (no sign-in) rather than falling back
          # to operator defaults during a datastore blip.
          return false if domain_id == DOMAIN_READ_FAILED

          signin_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id) if domain_id

          # Anything but a positively-classified operator host, with no opted-in
          # per-domain sign-in: password/email default OFF; keep the page only
          # when SSO is available.
          #
          # The predicate is operator_domain?, NOT tenant_domain? — this is the
          # display half of the pair, and it must branch on whatever
          # Base#signin_enabled? branches on.
          # ADR-024#display-runtime-parity
          if !operator_domain?(view_vars) && !signin_config&.enabled?
            return sso_available?(view_vars)
          end

          Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(global, signin_config)
        end

        # Whether any SSO sign-in method is available for the current request,
        # reusing build_sso_config so tenant SsoConfig, the sso_permitted_for?
        # activation gate, and platform fallback are all honored. Used by
        # resolve_signin to keep a custom domain's /signin page reachable for
        # SSO even when password/email sign-in is default-OFF.
        #
        # @param view_vars [Hash] View variables with request context
        # @return [Boolean] true if SSO providers are available
        def sso_available?(view_vars)
          sso = build_sso_config(view_vars)
          sso.is_a?(Hash) && sso['enabled'] == true
        end

        # Resolve email_auth availability for the current request context.
        #
        # AND semantics (differs from resolve_restrict_to's replace semantics):
        # a domain may DISABLE email_auth but cannot ENABLE it when the global
        # Rodauth route was never mounted. So the domain override only ever
        # narrows the global capability, never widens it.
        #
        # @param view_vars [Hash] View variables with request context
        # @return [Boolean] true if email_auth is available
        def resolve_email_auth(view_vars)
          global    = Onetime.auth_config.email_auth_enabled?
          domain_id = resolve_domain_id(view_vars)

          # Tri-state handling (#4157): failed read → narrow to off.
          return false if domain_id == DOMAIN_READ_FAILED

          signin_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id) if domain_id

          Onetime::CustomDomain::SigninConfig.resolve_email_auth_enabled(global, signin_config)
        end

        # Build SSO configuration for frontend
        #
        # Returns domain-aware SSO provider configuration. For custom domains
        # with CustomDomain::SsoConfig, returns the tenant's provider. Otherwise returns
        # platform SSO configuration (from env vars).
        #
        # Resolution priority:
        #   0. AUTH_ENABLED master switch off => disabled, unconditionally
        #   1. CustomDomain::SsoConfig for tenant (if custom domain with domain SSO config)
        #   2. Platform SSO providers (from env vars, if fallback allowed)
        #   3. Disabled (empty providers)
        #
        # @param view_vars [Hash] View variables containing domain context
        # @return [Boolean, Hash] false if disabled, otherwise config hash
        def build_sso_config(view_vars)
          # AUTH_ENABLED master switch: with authentication off there is no
          # SSO surface at all — tenant or platform — so return the disabled
          # shape before resolving anything. The tenant ladder
          # (SsoConfig.tenant_sso_unavailable_reason, rung :auth_disabled)
          # and build_platform_sso_config each enforce this too, but the
          # branches below must not depend on those internal checks: the
          # master switch is this method's own contract, guarded here.
          unless Onetime::CustomDomain::SigninConfig.global_auth_enabled
            return { 'enabled' => false, 'providers' => [] }
          end

          # Try tenant-specific SSO config first
          tenant_config = resolve_tenant_sso_config(view_vars)

          if tenant_config
            return build_tenant_sso_response(tenant_config)
          end

          # No tenant config resolved. Honor the operator's fallback policy:
          # when platform fallback is withheld from tenants, a host that is not
          # positively one of the operator's OWN gets no providers.
          #
          # The predicate is operator_domain?, NOT tenant_domain? — "may this
          # host borrow the platform's SSO providers" is an auth decision, and
          # the platform omniauth routes are host-independent, so a widen here
          # hands out a working sign-in method rather than a rendering detail.
          # ADR-024#operator-defaults-require-positive-classification
          #
          # Tenant-vs-platform SELECTION above is untouched and still keys on
          # domain identity (resolve_tenant_sso_config, via domain_id): a
          # genuinely unknown host has no tenant config to select, and this
          # guard is what decides whether it may fall back.
          if !operator_domain?(view_vars) && !allow_platform_fallback?
            return { 'enabled' => false, 'providers' => [] }
          end

          # Fall back to platform SSO config (from env vars)
          build_platform_sso_config
        end

        # Resolve tenant SSO configuration from request context
        #
        # Looks up CustomDomain::SsoConfig (credentials) for the custom domain
        # and gates it on SigninConfig.sso_permitted_for? — the shared
        # activation authority. Tenant SSO config is returned only when the
        # credentials store is enabled AND the SigninConfig permits SSO. Both
        # conditions are expressed through SsoConfig.tenant_sso_available_for?
        # (which also enforces the AUTH_ENABLED master switch), the single
        # source of truth this display half of the parity gate shares with the
        # branded-masthead link gate
        # (Core::Views::DomainSerializer#effective_signin_enabled?) and with
        # the runtime half in apps/web/auth/config/hooks/omniauth_tenant.rb,
        # which consults the same predicate. SigninConfig.sso_enabled
        # governs the TENANT's SSO only; build_sso_config's platform-fallback
        # policy is unchanged.
        #
        # Single-read contract: the record is loaded exactly once and handed
        # to the availability check via its sso_config: pass-through, so the
        # verdict and the returned record are the same object. Checking first
        # and re-loading after would leave a window where an operator
        # disabling or deleting the SsoConfig between the two reads passes the
        # check but returns nil — and build_sso_config would then silently
        # fall through to platform fallback for a domain that had tenant SSO
        # a moment earlier. The ladder (and that contract) now lives in
        # Onetime::TenantSsoResolution, resolved ONCE per request and shared
        # with AuthenticationSerializer#tenant_sso_enforced? and with
        # Onetime::Middleware::TenantCspExtras, which widens CSP form-action
        # with this same record's IdP origin (#4173) — the button and the
        # policy that lets its POST leave can no longer disagree. Tri-state
        # (#4157) is handled inside: a failed read yields nil here, the
        # narrowest surface.
        #
        # @param view_vars [Hash] View variables
        # @return [Onetime::CustomDomain::SsoConfig, nil] Config if found and enabled
        def resolve_tenant_sso_config(view_vars)
          tenant_sso_resolution(view_vars).sso_config
        end

        # The request-scoped tenant SSO resolution carried by view_vars
        # (installed by Core::Views::InitializeViewVars from the rack env), or
        # a fresh unshared one when view_vars was built without an env — same
        # answers, sharing is all that is lost.
        #
        # @param view_vars [Hash] View variables
        # @return [Onetime::TenantSsoResolution]
        def tenant_sso_resolution(view_vars)
          Onetime::TenantSsoResolution.from_view_vars(view_vars)
        end

        # Resolve domain identifier from view variables
        #
        # Returns the CustomDomain identifier when the lookup succeeds,
        # nil when the display_domain is blank or the domain doesn't exist,
        # or DOMAIN_READ_FAILED when the datastore read fails.
        #
        # Callers MUST check for DOMAIN_READ_FAILED and render the narrowest
        # surface (omit sign-in affordances) rather than treating a failed
        # read as "no tenant config" (#4157).
        #
        # Resolved once per request and memoized (Onetime::TenantSsoResolution),
        # so the four callers below — restrict_to, signin, email_auth and the
        # tenant SSO selection — all key on the SAME domain identity instead
        # of racing four independent reads.
        #
        # @param view_vars [Hash] View variables
        # @return [String, nil, :domain_read_failed]
        def resolve_domain_id(view_vars)
          tenant_sso_resolution(view_vars).domain_id
        end
        # ASYMMETRIC WITH THE GATES ON PURPOSE (#4139). The runtime gates raise
        # Onetime::SigninPolicyUnavailable when this same read fails, because a
        # gate that cannot read the policy must not decide. This is the DISPLAY
        # half: we return DOMAIN_READ_FAILED so callers can render the narrowest
        # surface (no sign-in affordance) rather than falling back to operator
        # defaults. The gate still catches any form submission with a 503, but
        # now the display layer agrees: unknown tenant policy means no sign-in
        # form, not the operator's default (#4157).

        # Check if request is from a tenant/custom domain
        #
        # @param view_vars [Hash] View variables
        # @return [Boolean] true if on a custom domain
        def tenant_domain?(view_vars)
          strategy = view_vars['domain_strategy']
          strategy == :custom
        end

        # Whether this request is positively classified as one of the operator's
        # OWN hosts, and may therefore inherit operator auth defaults.
        # ADR-024#identity-predicates-are-not-auth-gates
        #
        # The complement of tenant_domain? is NOT this: :invalid and nil
        # are neither operator hosts nor tenant hosts, and must be treated as
        # tenant-safe for auth while staying non-tenant for branding/routing.
        #
        # SigninConfig.operator_host? owns the classification list so this page
        # and the runtime gates cannot disagree about it.
        #
        # @param view_vars [Hash] View variables
        # @return [Boolean] true on :canonical / :subdomain
        def operator_domain?(view_vars)
          Onetime::CustomDomain::SigninConfig.operator_host?(view_vars['domain_strategy'])
        end

        # Check if platform fallback is allowed for tenant domains
        #
        # When true, custom domains without CustomDomain::SsoConfig use platform SSO.
        # When false, such domains see no SSO buttons.
        #
        # @return [Boolean] true if fallback allowed (default: false)
        def allow_platform_fallback?
          Onetime.auth_config.allow_platform_fallback_for_tenants?
        end

        # Build SSO response for tenant configuration
        #
        # @param config [Onetime::CustomDomain::SsoConfig] Tenant SSO config
        # @return [Hash] SSO config hash for frontend
        def build_tenant_sso_response(config)
          {
            'enabled' => true,
            'enforce_sso_only' => config.enforce_sso_only?,
            'providers' => [
              {
                'route_name' => config.platform_route_name,
                'display_name' => config.display_name.to_s,
              },
            ],
          }
        end

        # Transform domains config for frontend consumption
        #
        # Allowlist, not blocklist: the features.domains subtree includes the
        # Approximated proxy credentials and the internal ACME endpoint
        # config, which must never reach the bootstrap payload. The frontend
        # consumes validation_strategy (src/utils/features.ts) and the
        # optional require_verified/default fields; everything else stays
        # server-side.
        #
        # @param domains [Hash] Raw domains config from features
        # @return [Hash] Frontend-safe domains fields
        def transform_domains(domains)
          {
            'enabled' => domains.fetch('enabled', false),
            'require_verified' => domains.fetch('require_verified', false),
            'default' => domains['default'],
            'validation_strategy' => domains.fetch('validation_strategy', 'passthrough'),
          }
        end

        # Transform regions config for frontend consumption
        #
        # Passes through identifier, domain, icon, and i18n key.
        # Domain is public (users navigate to it directly).
        # Icons are optional; frontend falls back to src/sources/jurisdictions.ts.
        #
        # @param regions [Hash] Raw regions config from features
        # @return [Hash] Transformed regions with jurisdiction data
        def transform_regions(regions)
          jurisdictions = regions.fetch('jurisdictions', [])

          transformed_jurisdictions = jurisdictions.map do |j|
            identifier     = j['identifier'].to_s
            result         = {
              'identifier' => identifier,
              'domain' => j['domain'].to_s,
              'display_name_i18n_key' => j['display_name_i18n_key'] ||
                                         "web.regions.jurisdictions.#{identifier.downcase}.name",
            }
            result['icon'] = j['icon'] if j['icon'].is_a?(Hash)
            result
          end

          {
            'enabled' => regions.fetch('enabled', false),
            'current_jurisdiction' => regions['current_jurisdiction'],
            'jurisdictions' => transformed_jurisdictions,
          }
        end

        # Build platform SSO configuration from environment variables
        #
        # This is the original behavior - reading SSO providers from
        # AuthConfig which derives them from environment variables.
        #
        # Also gated on the AUTH_ENABLED master switch as defense in depth:
        # build_sso_config (the sole caller today) returns the disabled shape
        # before reaching here, but this builder must never advertise platform
        # providers on its own if it gains another caller — so it re-checks
        # rather than relying on the caller's guard.
        #
        # @return [Boolean, Hash] false if disabled, otherwise config hash
        def build_platform_sso_config
          unless Onetime::CustomDomain::SigninConfig.global_auth_enabled
            return { 'enabled' => false, 'providers' => [] }
          end

          return false unless Onetime.auth_config.sso_enabled?

          providers = Onetime.auth_config.sso_providers

          {
            'enabled' => true,
            'providers' => providers.map do |p|
              {
                'route_name' => p['route_name'].to_s,
                'display_name' => p['display_name'].to_s,
              }
            end,
          }
        end
      end

      SerializerRegistry.register(self)
    end
  end
end
