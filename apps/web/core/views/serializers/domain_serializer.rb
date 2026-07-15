# apps/web/core/views/serializers/domain_serializer.rb
#
# frozen_string_literal: true

require 'onetime/middleware/domain_strategy'
require 'onetime/logger_methods'
require 'onetime/models/custom_domain/signin_config'
require 'onetime/models/custom_domain/signup_config'
require 'onetime/models/custom_domain/sso_config'

module Core
  module Views
    # Serializes domain-related information for the frontend
    #
    # Handles custom domains, domain strategies, and domain branding
    # transformations for frontend consumption.
    module DomainSerializer
      extend Onetime::LoggerMethods

      # Serializes domain data from view variables
      #
      # Transforms domain strategy, custom domains, and domain branding
      # information into a consistent format for the frontend.
      #
      # @param view_vars [Hash] The view variables containing domain information
      # @return [Hash] Serialized domain data
      # rubocop:disable Metrics/PerceivedComplexity -- cohesive domain serialization; splitting would scatter related logic
      def self.serialize(view_vars)
        output                     = output_template
        output['domain_strategy']  = view_vars['domain_strategy']
        output['canonical_domain'] = Onetime::Middleware::DomainStrategy.canonical_domain
        output['display_domain']   = view_vars['display_domain']

        OT.ld "[DomainSerializer] domain_strategy=#{view_vars['domain_strategy'].inspect}, display_domain=#{view_vars['display_domain'].inspect}"

        apply_custom_domain(output) if output['domain_strategy'] == :custom
        apply_custom_domains_list(output, view_vars)
        apply_session_context(output, view_vars)

        output
      end
      # rubocop:enable Metrics/PerceivedComplexity

      class << self
        # Provides the base template for domain serializer output
        #
        # @return [Hash] Template with all possible domain output fields
        def output_template
          {
            'canonical_domain' => nil,
            'custom_domains' => nil,
            'display_domain' => nil,
            'domain_branding' => nil,
            'domain_id' => nil,
            'domain_locale' => nil,
            'domain_logo' => nil,
            'domain_context' => nil,
            'domain_strategy' => nil,
            'homepage_config' => nil,
          }
        end

        # Populates fields specific to the custom domain strategy.
        def apply_custom_domain(output)
          custom_domain             = Onetime::CustomDomain.from_display_domain(output['display_domain'])
          output['domain_id']       = custom_domain&.domainid
          output['domain_branding'] = build_branding_hash(custom_domain)

          apply_homepage_config(output, custom_domain) if custom_domain

          output['domain_locale'] = output['domain_branding'].fetch('locale', nil)
          output['domain_logo']   = build_domain_logo_url(custom_domain)
        end

        # Coerces Redis string boolean fields on a custom domain's brand settings.
        #
        # Strips the legacy allow_public_homepage / allow_public_api keys
        # (#3026): pre-cleanup Redis hashes may still carry them, but they're
        # no longer authoritative — HomepageConfig and ApiConfig are. Echoing
        # the stale values would re-introduce the dual source of truth.
        def build_branding_hash(custom_domain)
          branding_hash = (custom_domain&.brand&.hgetall || {}).to_h
          branding_hash.delete('allow_public_homepage')
          branding_hash.delete('allow_public_api')
          Onetime::CustomDomain::BrandSettingsConstants::BOOLEAN_FIELDS.each do |field|
            next unless branding_hash.key?(field)

            branding_hash[field] = Onetime::CustomDomain::BrandSettings.coerce_boolean(branding_hash[field])
          end
          branding_hash
        end

        # Loads homepage config from the dedicated model (authoritative source).
        def apply_homepage_config(output, custom_domain)
          homepage_config           = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(custom_domain.identifier)
          output['homepage_config'] = serialize_homepage_config(homepage_config, custom_domain)

          app_logger.debug '[DomainSerializer] homepage_config loaded',
            {
              domain: custom_domain.display_domain,
              homepage_config_exists: !homepage_config.nil?,
              enabled: homepage_config&.enabled?,
            }
        end

        def serialize_homepage_config(homepage_config, custom_domain)
          return nil unless homepage_config

          domain_id    = homepage_config.domain_id
          secrets_mode = homepage_config.secrets_mode_value

          # Effective enablement: a homepage pointed at the incoming form is
          # only interactive while incoming can actually receive secrets.
          # When that drifts (recipients removed, incoming disabled, config
          # deleted, feature flag turned off, entitlement lapsed), fail
          # closed to the non-interactive trust card — never fall open to
          # the create form the operator deliberately did not select, and
          # never let anonymous visitors see upgrade/misconfiguration copy
          # on the branded front door. The stored secrets_mode is preserved
          # so re-readying incoming restores the operator's intent.
          # HomepageConfig#effectively_enabled? is the single source of
          # truth, shared with the homepage-config API responses.
          effective_enabled = homepage_config.effectively_enabled?(custom_domain: custom_domain)

          # signup_enabled / signin_enabled drive the branded homepage
          # masthead auth links. They carry the effective_* value — custom
          # domains default OFF and only show a link when the domain owner has
          # explicitly enabled it via SigninConfig/SignupConfig (the
          # /domains/:id/signin + /signup settings pages), with the global
          # kill switch still able to force it off. This is NOT
          # HomepageConfig's own signup_enabled?/signin_enabled? fields —
          # those defaulted to false and had no settings-UI writer, so the
          # links never rendered.
          {
            'domain_id' => domain_id,
            'enabled' => effective_enabled,
            'secrets_mode' => secrets_mode,
            'signup_enabled' => effective_signup_enabled?(domain_id),
            'signin_enabled' => effective_signin_enabled?(domain_id),
            'disabled_homepage_variant' => homepage_config.disabled_homepage_variant_value,
            'created_at' => homepage_config.created&.to_i,
            'updated_at' => homepage_config.updated&.to_i,
          }
        end

        # Resolved sign-up availability for the branded homepage's Create
        # Account link. Custom domains default OFF: the branded front door
        # never advertises account creation unless the domain owner has
        # explicitly opted in via an enabled SignupConfig (the
        # /domains/:id/signup settings page). This is a deliberate divergence
        # from ADR-024 invariant #2 (which has unconfigured domains follow the
        # global default) — that invariant governs the canonical site's
        # display/runtime gates, not this branded masthead surface. When a
        # domain HAS opted in, the ADR-024 resolver still applies: the global
        # kill switch (AUTH_ENABLED && AUTH_SIGNUP) wins and the per-domain
        # value can only narrow, never widen.
        def effective_signup_enabled?(domain_id)
          config = Onetime::CustomDomain::SignupConfig.find_by_domain_id(domain_id)

          Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_custom_domain(
            Onetime::CustomDomain::SignupConfig.global_signup_enabled,
            config,
          )
        end

        # Resolved sign-in availability for the branded homepage's Sign In
        # link. Same default-OFF / opt-in polarity as effective_signup_enabled?:
        # hidden unless an enabled SigninConfig turns it on, and even then the
        # global AUTH_ENABLED && AUTH_SIGNIN kill switch still gates the result.
        #
        # The masthead link navigates to the /signin PAGE, so its visibility
        # must mirror the PAGE display gate (ConfigSerializer#resolve_signin),
        # NOT the POST /signin runtime gate (Core::Controllers::Base#signin_enabled?).
        # That is why this method reproduces resolve_signin's structure rather
        # than the runtime resolver: a custom domain with no enabled SigninConfig
        # defaults OFF for password/email but keeps the door open when tenant
        # SSO is available (SsoConfig.tenant_sso_available_for?), so an SSO-only
        # tenant (enabled SsoConfig, no SigninConfig) gets a working link to its
        # working /signin page. An *enabled* SigninConfig falls through to the
        # shared resolver, which honors an explicit signin_enabled=false and
        # hides SSO along with it (#3415) — matching resolve_signin exactly. SSO
        # itself signs in via the omniauth routes, never POST /signin, so the
        # POST handler correctly stays OFF for SSO-only tenants; that asymmetry
        # with this link gate is intentional. Platform-SSO fallback is out of
        # scope here by design (see SsoConfig.tenant_sso_available_for?).
        def effective_signin_enabled?(domain_id)
          config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id)

          unless config&.enabled?
            return Onetime::CustomDomain::SsoConfig.tenant_sso_available_for?(domain_id)
          end

          Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(
            Onetime::CustomDomain::SigninConfig.global_signin_enabled,
            config,
          )
        end

        # Use extid (external ID) for public URLs, not domainid (internal objid)
        def build_domain_logo_url(custom_domain)
          return nil if custom_domain&.logo&.[]('filename').to_s.empty?

          "/imagine/#{custom_domain.extid}/logo.png"
        end

        # Populates the authenticated user's custom domain list, if the feature is enabled.
        def apply_custom_domains_list(output, view_vars)
          return unless view_vars['authenticated']

          features        = view_vars['features'] || {}
          domains_enabled = features.dig('domains', 'enabled')
          return unless domains_enabled

          cust                     = view_vars['cust']
          output['custom_domains'] = cust.custom_domains_list.filter_map { |obj| serialize_domain_entry(obj) }.sort
        end

        # Returns the display_domain for a custom domain entry, logging unverified ones.
        def serialize_domain_entry(obj)
          # For now just log until we can reliably re-attempt verification and
          # have some visibility which customers this will affect. We've made
          # the verification more stringent so currently many existing domains
          # would return obj.ready? == false.
          unless obj.ready?
            app_logger.warn 'Serializing unverified custom domain',
              {
                domain: obj.display_domain,
                verified: obj.verified,
                resolving: obj.resolving,
              }
          end

          obj.display_domain
        end

        # Persists the user's domain context preference across pages/tabs/restarts.
        def apply_session_context(output, view_vars)
          return unless view_vars['authenticated']

          sess = view_vars['sess']
          return unless sess

          output['domain_context'] = sess['domain_context']
        end
      end

      SerializerRegistry.register(self, ['ConfigSerializer'])
    end
  end
end
