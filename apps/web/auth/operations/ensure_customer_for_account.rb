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

require 'auth/account_statuses'
require 'auth/operations/customers/purge'

module Auth
  module Operations
    class EnsureCustomerForAccount
      include Onetime::LoggerMethods

      # The record a sign-up with +email+ would meet, when it is marked as
      # closing (Customer#closing?); otherwise nil. Reads only:
      # finish_leftover_closure is the call that acts on it.
      def self.closing_customer(email)
        email    = OT::Utils.normalize_email(email)
        customer = Onetime::Customer.find_by_email(email) if Onetime::Customer.email_exists?(email)
        customer if customer&.closing?
      end

      # A record marked as closing under a sign-up's address is what a
      # closure left behind when it stopped after removing the sign-in and
      # before deleting the record (#4830). Its owner asked for it to be
      # deleted, so a new sign-up with the address does not adopt it, with
      # its data and its marker: the closure is finished through the same
      # purge `bin/ots customers finish-closures` runs, and the sign-up gets
      # a new record. The purge is the record's own (self_service:), as the
      # continuation of the closure it asked for.
      #
      # Every sign-up path calls this, and decides nothing about the record
      # itself: before_create_account (password sign-ups; the invite sign-up
      # endpoint refuses an address with any Customer record before it gets
      # there) and before_omniauth_create_account (SSO JIT) call it before
      # the accounts row exists, so a sign-up refused there leaves no row
      # behind. The call in find_or_create_customer below is a backstop for
      # a record marked between that check and the insert: by then the row
      # is committed, and all it can do is refuse to adopt the record.
      #
      # Only a closure Customer.closure_state classifies as :interrupted is
      # finished, as in Customers::FinishClosures. Two records are left
      # alone: a marker younger than Customer::CLOSURE_STALE_AFTER
      # (:in_progress), which can belong to a closure still running (an
      # administrative purge deletes the accounts row in its own transaction
      # before it deletes the record), and a marked record with an open
      # accounts row of its own (:rolled_back). The sign-up is refused
      # instead, and a retry once the marker is old enough finishes the
      # first.
      #
      # @param email [String] the sign-up's address
      # @return [Onetime::Customer, nil] the closing record when it is still
      #   there afterwards (left alone, or the purge stopped), and the
      #   sign-up must be refused; nil when no record under the address was
      #   closing or the closure is now finished
      def self.finish_leftover_closure(email)
        leftover = closing_customer(email)
        leftover unless leftover.nil? || finish_interrupted_closure(leftover)
      end

      # @return [Boolean] true when +customer+ is gone afterwards
      def self.finish_interrupted_closure(customer)
        state = customer.closure_state(open_auth_account: open_auth_account?(customer))
        unless state == :interrupted
          # A sign-up inside a running closure's window is the design at
          # work; a rolled-back closure or an unreadable account is not.
          Auth::Logging.log_auth_event(
            :interrupted_closure_not_finished,
            level: state == :in_progress ? :info : :error,
            external_id: customer.extid,
            closure_state: state,
          )
          return false
        end

        result   = Auth::Operations::Customers::Purge.new(
          customer: customer,
          self_service: true,
          reason: 'finish an interrupted closure before a sign-up with the same address',
        ).call
        finished = !customer.exists?

        Auth::Logging.log_auth_event(
          finished ? :interrupted_closure_finished : :interrupted_closure_not_finished,
          level: finished ? :info : :error,
          external_id: customer.extid,
          status: result.status,
          stage: result.stage,
          blockers: result.blockers,
        )
        finished
      end
      private_class_method :finish_interrupted_closure

      def self.open_auth_account?(customer)
        return false unless Onetime.auth_config.full_enabled?

        Auth::Database.connection[:accounts]
          .where(external_id: customer.extid, status_id: Auth::AccountStatuses::LIVE)
          .any?
      end
      private_class_method :open_auth_account?

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

        # A record still closing under the address is finished first, and
        # never adopted (see finish_leftover_closure).
        unfinished = self.class.finish_leftover_closure(email)
        if unfinished
          raise Onetime::Problem, "The interrupted closure of #{unfinished.extid} could not be finished"
        end

        existing = Onetime::Customer.find_by_email(email) if Onetime::Customer.email_exists?(email)
        if existing
          auth_logger.info "[create-customer] Found existing customer: #{existing.custid}"
          return existing
        end

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
