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

        output['authenticated'] = view_vars['authenticated']
        cust = view_vars['cust'] || V2::Customer.anonymous

        output['cust'] = cust.safe_dump

        if output['authenticated']
          output['custid'] = cust.custid
          output['email'] = cust.email
          output['customer_since'] = OT::Utils::TimeUtils.epochdom(cust.created)
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
