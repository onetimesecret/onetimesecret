# apps/web/auth/operations/ensure_customer_for_account.rb
#
# frozen_string_literal: true

#
# Creates or loads a Customer record and links it to a Rodauth account.
# This operation is typically called after account creation.
#
# Log tag `[create-customer]` is kept as a stable operational identifier
# (correlates current and historical activity; renaming this class must not
# silently invalidate saved searches, dashboards, alerts, or runbooks). It
# intentionally does not track the class name.
#

module Auth
  module Operations
    class EnsureCustomerForAccount
      include Onetime::LoggerMethods

      # @param account_id [Integer] The ID of the Rodauth account
      # @param account [Hash] The Rodauth account hash, containing at least :email
      # @param db [Sequel::Database] The database connection (optional)
      # @param provisioning_origin [String, nil] One of Onetime::Customer::PROVISIONING_ORIGINS.
      #   Set on newly-created Customer records as lifecycle/audit metadata.
      #   Ignored when the customer already exists (we don't rewrite history).
      # @param signup_domain_id [String, nil] CustomDomain identifier captured at signup.
      #   Set on newly-created Customer records. Ignored for existing customers to
      #   preserve original signup context (same "don't rewrite history" rule as
      #   provisioning_origin).
      # @param verified [Boolean] Initial verification state for a NEWLY-created
      #   Customer. Defaults to false — the password-signup shape, where
      #   Rodauth's after_verify_account flips the flag once the emailed link is
      #   followed. A caller passes true ONLY when the account is already
      #   verified at creation time and no later hook will do it (the SSO/JIT
      #   path: Rodauth opens the account at AccountStatuses::VERIFIED and never
      #   fires after_verify_account). Ignored when the customer already exists —
      #   same "don't rewrite history" rule as provisioning_origin, and it keeps
      #   this operation from silently upgrading an existing unverified record.
      # @param verified_by [String, nil] Provenance tag stored alongside
      #   `verified` (see Auth::Operations::Customers::Doctor::VALID_VERIFIED_BY).
      #   Only meaningful when verified: true.
      # @param verification_hold [String, nil] One of
      #   Onetime::Customer::VERIFICATION_HOLDS. The SSO/JIT caller passes it
      #   when it deliberately left the Customer unverified — the IdP asserted
      #   email_verified: false, or the claim could not be read — so the record
      #   carries WHY and the customers doctor never auto-"repairs" that
      #   decision away. Contradicts verified: true (ArgumentError). Ignored
      #   for existing customers (same "don't rewrite history" rule as
      #   provisioning_origin).
      # @raise [ArgumentError] unknown verification_hold, or a hold combined
      #   with verified: true — refused before any lookup or write
      def initialize(account_id:, account:, db: nil, provisioning_origin: nil, signup_domain_id: nil,
                     verified: false, verified_by: nil, verification_hold: nil)
        Onetime::Customer.assert_known_verification_hold!(verification_hold)
        if verified && !verification_hold.to_s.empty?
          raise ArgumentError,
            "verification_hold #{verification_hold.inspect} contradicts verified: true"
        end

        @account_id          = account_id
        @account             = account
        @db                  = db || Auth::Database.connection
        @provisioning_origin = provisioning_origin
        @signup_domain_id    = signup_domain_id
        @verified            = verified ? true : false
        @verified_by         = @verified ? verified_by : nil
        @verification_hold   = verification_hold.to_s.empty? ? nil : verification_hold.to_s
      end

      # Executes the customer creation/loading operation
      # @return [Onetime::Customer] The created or existing customer
      def call
        customer = find_or_create_customer

        link_to_rodauth_account(customer)
        verify_link(customer)

        customer
      end

      private

      # Finds existing customer or creates a new one
      # @return [Onetime::Customer]
      def find_or_create_customer
        # Normalize once so the lookup matches create!'s normalized email index
        # (Customer.create! normalizes before keying email_index). Without this a
        # mixed-case email misses the find branch and re-enters create!, raising
        # RecordExistsError. exists?(identifier) checks objid, never the email
        # index, so we must use email_exists?/find_by_email here.
        email = OT::Utils.normalize_email(@account[:email])

        if Onetime::Customer.email_exists?(email)
          customer = Onetime::Customer.find_by_email(email)
          auth_logger.info "[create-customer] Found existing customer: #{customer.custid}"
        else
          # New accounts default to 'customer' role. Colonel promotion
          # is handled exclusively via CLI: bin/ots customers role promote user@example.com
          customer = Onetime::Customer.create!(
            email: email,
            role: 'customer',
            # Default false: the password-signup shape, flipped later by
            # after_verify_account. True only when the caller has already
            # established verification (see the `verified:` param docs).
            verified: @verified,
            verified_by: @verified_by,
            verification_hold: @verification_hold,
            provisioning_origin: @provisioning_origin,
            signup_domain_id: @signup_domain_id,
          )

          auth_logger.info "[create-customer] Created new customer: #{customer.custid} (role: customer, " \
                           "origin: #{@provisioning_origin || 'unknown'}, " \
                           "signup_domain_id: #{@signup_domain_id || 'none'}, " \
                           "verified: #{@verified}, verified_by: #{@verified_by || 'none'}, " \
                           "verification_hold: #{@verification_hold || 'none'})"
        end

        customer
      end

      # Links the customer to the Rodauth account via external_id
      # @param customer [Onetime::Customer]
      def link_to_rodauth_account(customer)
        rows_updated = @db[:accounts]
          .where(id: @account_id)
          .update(external_id: customer.extid)
        auth_logger.info "[create-customer] Linked Rodauth account #{@account_id} to extid: #{customer.extid} (rows_updated: #{rows_updated})"
      end

      # Verifies the link was created successfully
      # @param customer [Onetime::Customer]
      def verify_link(customer)
        stored_extid = @db[:accounts]
          .where(id: @account_id)
          .get(:external_id)

        auth_logger.info "[create-customer] Verification - stored external_id: #{stored_extid}"

        unless stored_extid == customer.extid
          OT.le "[create-customer] WARNING: external_id mismatch! Expected #{customer.extid}, got #{stored_extid}"
        end
      end
    end
  end
end
