# lib/onetime/models/customer/features/colonel_assignment.rb
#
# frozen_string_literal: true

# Colonel Auto-Assignment Feature
#
# Determines if a newly created customer should be assigned the colonel
# (superuser) role based on the configured colonels list.
#
# The colonels list is configured via:
# - ENV['COLONEL'] environment variable
# - Parsed into site.authentication.colonels in config
#
# Security considerations:
# - Email must be normalized identically to config values
# - Uses Unicode case folding for international email addresses
# - Explicit audit logging for privilege escalation events
#
# Used by:
# - CreateCustomer operation (full auth mode)
# - CreateAccount logic (simple auth mode)
#
module Onetime
  class Customer
    module Features
      module ColonelAssignment
        extend self

        # Determine the appropriate role for a new customer based on email
        #
        # @param email [String] The normalized email address
        # @return [String] 'colonel' if email matches config, 'customer' otherwise
        def determine_role(email)
          return 'customer' if email.nil? || email.empty?

          colonel?(email) ? 'colonel' : 'customer'
        end

        # Check if an email address is in the colonels list
        #
        # @param email [String] The email to check (should be pre-normalized)
        # @return [Boolean] true if email matches a configured colonel
        def colonel?(email)
          return false if email.nil? || email.empty?

          normalized_email = normalize_email(email)
          colonels_list.include?(normalized_email)
        end

        # Get the normalized colonels list from config
        #
        # @return [Array<String>] Normalized email addresses
        def colonels_list
          raw_list = OT.conf.dig('site', 'authentication', 'colonels') || []

          raw_list.map { |col| normalize_email(col) }.compact.reject(&:empty?)
        end

        # Normalize an email for consistent comparison
        #
        # Applies the same normalization as Customer.create!:
        # - Strip whitespace
        # - NFC Unicode normalization
        # - Unicode case folding (handles international characters)
        #
        # @param email [String] Raw email address
        # @return [String] Normalized email address
        def normalize_email(email)
          email.to_s.strip.unicode_normalize(:nfc).downcase(:fold)
        end

        # Assign colonel role if email matches, with audit logging
        #
        # @param customer [Onetime::Customer] The customer to potentially promote
        # @param email [String] The normalized email address
        # @return [Boolean] true if colonel role was assigned
        def assign_if_colonel(customer, email)
          return false unless colonel?(email)

          customer.role = 'colonel'

          Onetime.auth_logger.warn 'SECURITY: Colonel role auto-assigned',
            {
              customer_id: customer.custid,
              email: OT::Utils.obscure_email(email),
              action: 'colonel_auto_assign',
              verified: customer.verified?,
            }

          true
        end
      end
    end
  end
end
