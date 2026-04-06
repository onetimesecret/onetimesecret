# lib/onetime/models/customer/features/colonel_assignment.rb
#
# frozen_string_literal: true

# Colonel Auto-Assignment Feature
#
# Manages colonel (superuser) role assignment based on the configured
# colonels list. Handles both initial assignment at creation time and
# ongoing enforcement (promotion/demotion) on login.
#
# The colonels list is configured via:
# - ENV['COLONEL'] environment variable
# - Parsed into site.authentication.colonels in config
#
# The COLONEL env var is the source of truth for colonel status.
# Removing an email from the env var will demote the customer on
# next login. Use the 'admin' role for permanent elevated access
# that is not managed by this module.
#
# Security considerations:
# - Email must be normalized identically to config values
# - Uses Unicode case folding for international email addresses
# - Explicit audit logging for all role transitions
# - Admin role is never modified by this module
#
# Used by:
# - CreateCustomer operation (full auth mode signup)
# - SyncSession operation (full auth login)
# - CreateAccount logic (simple auth mode signup)
#
module Onetime
  class Customer
    module Features
      module ColonelAssignment
        extend self

        # Determine the appropriate role for a new customer based on email.
        # Used at creation time before a customer object exists.
        #
        # @param email [String] The normalized email address
        # @return [String] 'colonel' if email matches config, 'customer' otherwise
        def determine_role(email)
          return 'customer' if email.nil? || email.empty?

          colonel?(email) ? 'colonel' : 'customer'
        end

        # Ensure customer's colonel role matches the colonels config list.
        # Used on existing customers at login/sync time.
        #
        # - Promotes to colonel if email is in the list and role is not colonel/admin
        # - Demotes to customer if email is NOT in the list and role is colonel
        # - Never modifies admin role (admin supersedes colonel)
        #
        # @param customer [Onetime::Customer] The customer to check
        # @param context [String] Caller context for audit logging
        # @return [Symbol, nil] :promoted, :demoted, or nil if no change
        def ensure_colonel_role(customer, context:)
          return nil if customer.nil?
          return nil if customer.role.to_s == 'admin'

          email_in_list = colonel?(customer.email)
          current_role  = customer.role.to_s

          if email_in_list && current_role != 'colonel'
            previous_role = current_role
            customer.role = 'colonel'
            customer.save

            Onetime.auth_logger.warn 'SECURITY: Customer promoted to colonel',
              {
                customer_id: customer.custid,
                email: customer.obscure_email,
                action: 'colonel_promotion',
                context: context,
                previous_role: previous_role,
              }

            :promoted

          elsif !email_in_list && current_role == 'colonel'
            customer.role = 'customer'
            customer.save

            Onetime.auth_logger.warn 'SECURITY: Customer demoted from colonel (not in colonels list)',
              {
                customer_id: customer.custid,
                email: customer.obscure_email,
                action: 'colonel_demotion',
                context: context,
                previous_role: 'colonel',
              }

            :demoted
          end
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
        # Handles both YAML array entries and comma-separated values within entries.
        # This supports the common pattern: COLONEL=admin@example.com,backup@example.com
        #
        # @return [Array<String>] Normalized email addresses
        def colonels_list
          raw_list = OT.conf.dig('site', 'authentication', 'colonels') || []

          # Flatten comma-separated values and normalize each email
          raw_list
            .flat_map { |entry| entry.to_s.split(',') }
            .map { |col| normalize_email(col) }
            .compact
            .reject(&:empty?)
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
      end
    end
  end
end
