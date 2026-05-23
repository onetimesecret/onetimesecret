# apps/web/auth/operations/set_customer_verification.rb
#
# frozen_string_literal: true

#
# Sets a Customer's verification state across both stores: the Familia
# Customer record in Redis and (in full auth mode) the Rodauth accounts
# row in SQL. Designed as the single home for manual/admin verification
# changes — callable from CLI today and from the Colonel admin API
# (apps/api/colonel/logic/) when that surface is added.
#
# Distinct from Auth::Operations::VerifyCustomer, which is a Rodauth
# after_verify_account callback adapter (Rodauth has already flipped
# status_id; the op mirrors that to Redis with verified_by='email').
# This op drives the change in the opposite direction: caller has a
# Customer and wants to set verification state on both sides.
#
# Cross-store consistency notes (Familia v2.9.1):
#   Familia is Redis-only — no cross-store transaction primitive
#   exists. save_with_collections is for scalar+collection co-writes
#   on a single Familia object, not Redis+SQL. We achieve consistency
#   with application-level ordering: SQL update first (inside
#   db.transaction for SQL-side atomicity), Redis save second.
#
#   Failure modes:
#     - SQL raises  → Redis untouched (clean rollback)
#     - No SQL row  → AccountNotFound, Redis untouched
#     - SQL ok, Redis raises → Rodauth fresh, Customer stale.
#       Auth state (the important one) is correct; display of
#       Customer#verified? will be wrong until next save.
#       Detectable and fixable via `bin/ots customers sync-auth-accounts`.
#

module Auth
  module Operations
    class SetCustomerVerification
      include Onetime::LoggerMethods

      class NoAuthDatabase < StandardError; end
      class AccountNotFound < StandardError; end

      # @param customer    [Onetime::Customer] target (caller ensures non-nil,
      #                    non-anonymous)
      # @param verified    [Boolean] target state
      # @param verified_by [String, nil] provenance tag ('cli_provision',
      #                    'colonel_admin', etc.); nil when clearing
      # @param db          [Sequel::Database, nil] injectable for tests and
      #                    callers with an existing connection; defaults to
      #                    Auth::Database.connection at call time
      def initialize(customer:, verified:, verified_by:, db: nil)
        @customer    = customer
        @verified    = verified
        @verified_by = verified_by
        @db          = db
      end

      # @return [Symbol] :success or :no_change
      # @raise [NoAuthDatabase] full auth mode + DB unreachable
      # @raise [AccountNotFound] full auth mode + no accounts row for email
      def call
        return :no_change if @customer.verified? == @verified

        update_rodauth_account! if full_auth_mode?
        update_customer!

        auth_logger.info "[set-customer-verification] #{@customer.objid} " \
          "verified=#{@verified} verified_by=#{@verified_by.inspect} " \
          "auth_mode=#{Onetime.auth_config.mode}"
        :success
      end

      private

      def full_auth_mode?
        Onetime.auth_config.mode == 'full'
      end

      def update_rodauth_account!
        db = @db || Auth::Database.connection
        raise NoAuthDatabase, 'Auth database unreachable' unless db

        rows = db.transaction do
          db[:accounts]
            .where(email: @customer.email)
            .update(status_id: @verified ? 2 : 1, updated_at: Time.now)
        end
        return unless rows.zero?

        raise AccountNotFound, "No Rodauth account for #{@customer.email}"
      end

      def update_customer!
        @customer.verified    = @verified
        @customer.verified_by = @verified_by
        @customer.save
      end
    end
  end
end
