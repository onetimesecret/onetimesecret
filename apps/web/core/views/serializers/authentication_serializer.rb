# apps/web/core/views/serializers/authentication_serializer.rb

require 'onetime/utils'

module Core
  module Views
    # Serializes authentication-related data for the frontend
    #
    # Responsible for transforming customer authentication state and
    # associated customer data into a consistent format for frontend consumption.
    module AuthenticationSerializer
      # Serializes authentication data from view variables
      #
      # @param view_vars [Hash] The view variables containing authentication state
      # @param i18n [Object] The internationalization instance
      # @return [Hash] Serialized authentication data including customer information
      def self.serialize(view_vars, i18n)
        output = self.output_template

        output[:authenticated] = view_vars[:authenticated]
        output[:cust] = view_vars[:cust] || V2::Customer.anonymous

        if output[:authenticated]
          cust = output[:cust]

          output[:custid] = cust.custid
          output[:cust] = cust.safe_dump
          output[:email] = cust.email
          output[:customer_since] = OT::TimeUtils.epochdom(cust.created)

          if view_vars[:domains_enabled]
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
        end

        output
      end

      private

      # Provides the base template for authentication serializer output
      #
      # @return [Hash] Template with all possible authentication output fields
      def self.output_template
        {
          authenticated: 'plop',
          custid: nil,
          cust: nil,
          email: nil,
          customer_since: nil,
          custom_domains: nil,
        }
      end

      SerializerRegistry.register(self)
    end
  end
end
