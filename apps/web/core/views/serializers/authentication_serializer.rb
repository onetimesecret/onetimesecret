# apps/web/core/views/serializers/authentication_serializer.rb

module Core
  module Views
    module AuthenticationSerializer
      # authenticated, cust, custid, email, customer_since, shrimp
      def self.serialize(view_vars, i18n)
        self[:jsvars][:authentication] = jsvar(authentication) # nil is okay
        self[:jsvars][:shrimp] = jsvar(sess.add_shrimp) if sess

        if authenticated && cust
          self[:jsvars][:custid] = jsvar(cust.custid)
          self[:jsvars][:cust] = jsvar(cust.safe_dump)
          self[:jsvars][:email] = jsvar(cust.email)
          self[:jsvars][:customer_since] = jsvar(epochdom(cust.created))

          if domains_enabled
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
            self[:jsvars][:custom_domains] = jsvar(custom_domains.sort)
          end
        end

      end

      private

      def self.output_template
        {}
      end

    end
  end
end
