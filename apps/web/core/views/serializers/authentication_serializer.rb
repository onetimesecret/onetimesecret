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
      def self.serialize(view_vars, _i18n)
        output = output_template

        output['authenticated'] = view_vars['authenticated']
        output['awaiting_mfa']  = view_vars['awaiting_mfa'] || false
        cust                    = view_vars['cust'] || Onetime::Customer.anonymous

        output['cust'] = cust.safe_dump

        # When awaiting_mfa is true, user has passed first factor (email/password)
        # but needs to complete second factor (TOTP/WebAuthn) before full access
        if output['authenticated'] || output['awaiting_mfa']
          output['custid']         = cust.custid
          output['email']          = cust.email
          output['customer_since'] = OT::Utils::TimeUtils.epochdom(cust.created) if cust.created
        end

        output
      end

      class << self
        # Provides the base template for authentication serializer output
        #
        # @return [Hash] Template with all possible authentication output fields
        def output_template
          {
            'authenticated' => nil,
            'awaiting_mfa' => false,
            'custid' => nil,
            'cust' => nil,
            'email' => nil,
            'customer_since' => nil,
          }
        end
      end

      SerializerRegistry.register(self)
    end
  end
end
