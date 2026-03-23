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
      # @return [Hash] Serialized authentication data including customer information
      def self.serialize(view_vars)
        output = output_template

        output['authenticated'] = view_vars['authenticated']
        output['awaiting_mfa']  = view_vars['awaiting_mfa'] || false
        cust                    = view_vars['cust']

        # For anonymous users (nil cust), provide minimal anonymous representation
        output['cust'] = cust ? cust.safe_dump : anonymous_safe_dump

        # Check if there was a valid session at the time of this response
        # This is crucial for error pages where authenticated=false but the user
        # had a valid session. The frontend uses this to avoid incorrect logouts.
        # A valid session has 'external_id' present (customer identifier in session)
        sess                        = view_vars['sess']
        output['had_valid_session'] = !!(sess && !sess.empty? && !sess['external_id'].to_s.empty?)

        # When authenticated, provide full customer data
        if output['authenticated']
          output['custid']         = cust.custid
          output['email']          = cust.email
          # customer_since: Formatted date string (e.g., "Mar 21, 2026") - matches Zod schema z.string()
          output['customer_since'] = OT::Utils::TimeUtils.epochdom(cust.created) if cust.created
          output['has_password']   = account_has_password?(sess)

          # Add entitlement test mode state for colonels
          if cust.role?(:colonel) && sess[:entitlement_test_planid]
            test_planid    = sess[:entitlement_test_planid]
            test_plan_name = resolve_test_plan_name(test_planid)

            if test_plan_name
              output['entitlement_test_planid']    = test_planid
              output['entitlement_test_plan_name'] = test_plan_name
            end
          end

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
            'had_valid_session' => false,
            'has_password' => false,
            'custid' => nil,
            'cust' => nil,
            'email' => nil,
            'customer_since' => nil,
            'entitlement_test_planid' => nil,
            'entitlement_test_plan_name' => nil,
          }
        end

        # Checks whether the authenticated account has a password hash set.
        # SSO-only accounts have no row in account_password_hashes.
        #
        # @param sess [Hash, nil] Session hash containing account_id
        # @return [Boolean] true if account has a password, false otherwise
        def account_has_password?(sess)
          account_id = sess&.[]('account_id')
          return false unless account_id

          db = Auth::Database.connection
          return false unless db

          db[:account_password_hashes].where(id: account_id).any?
        rescue StandardError
          false
        end

        # Provides minimal safe_dump representation for anonymous users
        #
        # When cust is nil (anonymous), we provide a minimal structure matching
        # the Customer.safe_dump format that the frontend expects.
        #
        # @return [Hash] Minimal anonymous customer representation
        def anonymous_safe_dump
          {
            'objid' => nil,
            'extid' => nil,
            'email' => nil,
            'role' => 'anonymous',
            'verified' => false,
            'last_login' => nil,
            'locale' => nil,
            'updated' => nil,
            'created' => nil,
            'secrets_created' => '0',
            'secrets_burned' => '0',
            'secrets_shared' => '0',
            'emails_sent' => '0',
            'active' => false,
            'notify_on_reveal' => false,
          }
        end

        # Resolve test plan name from Billing::Plan cache or config
        #
        # Uses centralized fallback loader to try Stripe cache first,
        # then billing.yaml config for development/standalone environments.
        #
        # @param test_planid [String] Plan ID to resolve
        # @return [String, nil] Plan name or nil if not found
        def resolve_test_plan_name(test_planid)
          result = ::Billing::Plan.load_with_fallback(test_planid)
          result[:plan]&.name || result[:config]&.dig(:name)
        end
      end

      SerializerRegistry.register(self)
    end
  end
end
