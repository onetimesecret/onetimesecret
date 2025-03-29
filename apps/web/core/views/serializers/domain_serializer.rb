# apps/web/core/views/serializers/domain_serializer.rb

require 'v2/models/custom_domain'
require 'onetime/middleware/domain_strategy'

module Core
  module Views
    module DomainSerializer
      # - canonical_domain, domain_strategy, domain_id, display_domain, domain_branding, domain_logo
      # - custom_domains
      def self.serialize(view_vars, i18n)
        output = self.output_template

        output[:domain_strategy] = view_vars[:domain_strategy]

        output[:canonical_domain] = Onetime::DomainStrategy.canonical_domain
        output[:display_domain] = view_vars[:display_domain]

        # Custom domain handling
        if output[:domain_strategy] == :custom
          # Load the CustomDomain object
          output[:custom_domain] = V2::CustomDomain.from_display_domain(output[:display_domain])
          output[:domain_id] = custom_domain&.domainid
          output[:domain_branding] = (custom_domain&.brand&.hgetall || {}).to_h
          output[:domain_logo] = (custom_domain&.logo&.hgetall || {}).to_h

          domain_locale = domain_branding.fetch('locale', nil)
        end

      end

      private

      def self.output_template
        {
          canonical_domain: nil,
          custom_domain: nil,
          display_domain: nil,
          domain_branding: {},
          domain_id: nil,
          domain_locale: nil,
          domain_logo: {},
          domain_strategy: nil,
          # Were in original implementation, now removed:
          # display_locale: nil,
          # is_default_locale: nil,
        }
      end

    end
  end
end
