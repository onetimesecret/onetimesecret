# apps/web/core/views/serializers/authentication_serializer.rb

require 'onetime/utils'

module Core
  module Views
    module AuthenticationSerializer
      # authenticated, cust, custid, email, customer_since
      def self.serialize(view_vars, i18n)
        output = self.output_template

        authenticated = view_vars[:authenticated]
        cust = view_vars[:cust]

        if authenticated && cust
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

      def self.output_template
        {
          authenticated: false,
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
