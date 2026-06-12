# apps/web/core/views/serializers/domain_serializer.rb
#
# frozen_string_literal: true

require 'onetime/middleware/domain_strategy'
require 'onetime/logger_methods'

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
          output['homepage_config'] = serialize_homepage_config(homepage_config)

          app_logger.debug '[DomainSerializer] homepage_config loaded',
            {
              domain: custom_domain.display_domain,
              homepage_config_exists: !homepage_config.nil?,
              enabled: homepage_config&.enabled?,
            }
        end

        def serialize_homepage_config(homepage_config)
          return nil unless homepage_config

          {
            'domain_id' => homepage_config.domain_id,
            'enabled' => homepage_config.enabled?,
            'signup_enabled' => homepage_config.signup_enabled?,
            'signin_enabled' => homepage_config.signin_enabled?,
            'disabled_homepage_variant' => homepage_config.disabled_homepage_variant_value,
            'created_at' => homepage_config.created&.to_i,
            'updated_at' => homepage_config.updated&.to_i,
          }
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
