# apps/web/core/views/serializers/domain_serializer.rb

require 'v2/models/custom_domain'
require 'onetime/middleware/domain_strategy'

module Core
  module Views

    # Serializes domain-related information for the frontend
    #
    # Handles custom domains, domain strategies, and domain branding
    # transformations for frontend consumption.
    module DomainSerializer

      # Serializes domain data from view variables
      #
      # Transforms domain strategy, custom domains, and domain branding
      # information into a consistent format for the frontend.
      #
      # @param view_vars [Hash] The view variables containing domain information
      # @param i18n [Object] The internationalization instance
      # @return [Hash] Serialized domain data
      def self.serialize(view_vars, i18n)
        output = self.output_template

        is_authenticated = view_vars[:authenticated]
        domains = view_vars[:site].fetch(:domains, {})
        cust = view_vars[:cust]

        output[:domain_strategy] = view_vars[:domain_strategy]

        output[:canonical_domain] = Onetime::DomainStrategy.canonical_domain
        output[:display_domain] = view_vars[:display_domain]

        # Custom domain handling
        if output[:domain_strategy] == :custom
          # Load the CustomDomain object
          custom_domain = V2::CustomDomain.from_display_domain(output[:display_domain])
          output[:domain_id] = custom_domain&.domainid
          output[:domain_branding] = (custom_domain&.brand&.hgetall || {}).to_h
          output[:domain_logo] = (custom_domain&.logo&.hgetall || {}).to_h

          domain_locale = output[:domain_branding].fetch('locale', nil)
        end

        # There's no custom domain list when the feature is disabled.
        if is_authenticated && domains[:enabled]
          custom_domains = cust.custom_domains_list.filter_map do |obj|
            # Only verified domains that resolve
            unless obj.ready?
              # For now just log until we can reliably re-attempt verification and
              # have some visibility which customers this will affect. We've made
              # the verification more stringent so currently many existing domains
              # would return obj.ready? == false.
              OT.li "[custom_domains] Allowing unverified domain: #{obj.display_domain} (#{obj.verified}/#{obj.resolving})"
            end

            obj.display_domain
          end
          output[:custom_domains] = custom_domains.sort
        end

        output
      end

      private

      # Provides the base template for domain serializer output
      #
      # @return [Hash] Template with all possible domain output fields
      def self.output_template
        {
          canonical_domain: nil,
          custom_domains: nil,
          display_domain: nil,
          domain_branding: nil,
          domain_id: nil,
          domain_locale: nil,
          domain_logo: nil,
          domain_strategy: nil,
          # Were in original implementation, now removed:
          # display_locale: nil,
        }
      end

      SerializerRegistry.register(self, ['ConfigSerializer'])
    end
  end
end
