# apps/web/core/views/serializers/authentication_serializer.rb
#
# frozen_string_literal: true

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

        # When authenticated, provide full customer data
        if output['authenticated']
          output['custid']         = cust.custid
          output['email']          = cust.email
          output['customer_since'] = OT::Utils::TimeUtils.epochdom(cust.created) if cust.created

        # When awaiting MFA, provide minimal data from session (no customer access yet)
        elsif output['awaiting_mfa']
          output['email'] = view_vars['session_email']  # From session, not customer
          # Do NOT provide custid or customer object - user doesn't have access yet
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
