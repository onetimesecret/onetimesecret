# apps/web/auth/operations/teardown_account.rb
#
# frozen_string_literal: true

require 'auth/operations/close_account'
require 'auth/operations/delete_customer_record'
require 'onetime/operations/sessions/revoke_all_for_customer'
require 'onetime/operations/sessions/revoke_all_for_customer_except_current'

module Auth
  module Operations
    # Permanently removes one account through the same ordered teardown in every
    # authentication mode and from both self-service and administrative callers.
    #
    # The operation revokes sessions first, closes the Rodauth identity and removes
    # its credentials when full auth is enabled, and deletes the Redis Customer
    # last. Rodauth invokes its
    # after_close_account hook inside the SQL transaction; that caller supplies the
    # same database handle so a later Redis cleanup failure aborts the SQL closure.
    #
    # Colonel auditing remains in Customers::Purge. Supplying actor selects the
    # audited administrative session-revocation operation; self-service callers do
    # not write to the Colonel audit trail.
    class TeardownAccount
      Result = Data.define(:status, :extid, :custid, :account_id)

      def initialize(customer: nil, account: nil, actor: nil, reason: nil, db: nil)
        raise ArgumentError, 'Must provide either customer: or account:' if customer.nil? && account.nil?
        raise ArgumentError, 'Cannot provide both customer: and account:' if customer && account

        @customer = customer
        @account  = account
        @actor    = actor
        @reason   = reason
        @db       = db
      end

      def call
        customer = @customer || find_customer
        unless customer
          account_id = close_auth_account(account_extid)
          status     = @account && full_auth_mode? ? :success : :not_found
          return Result.new(status: status, extid: account_extid, custid: nil, account_id: account_id)
        end

        extid  = customer.extid
        custid = customer.custid

        revoke_sessions(customer)
        account_id = close_auth_account(extid)
        deleted    = Auth::Operations::DeleteCustomerRecord.new(customer: customer).call

        status = deleted ? :success : :not_found
        Result.new(status: status, extid: extid, custid: custid, account_id: account_id)
      end

      private

      def find_customer
        customer = Onetime::Customer.find_by_extid(account_extid) unless account_extid.to_s.empty?
        return customer if customer
        return nil if @account[:email].to_s.empty?

        Onetime::Customer.find_by_email(@account[:email])
      end

      def account_extid
        @account&.[](:external_id)
      end

      def revoke_sessions(customer)
        if @actor
          Onetime::Operations::Sessions::RevokeAllForCustomer.new(
            customer: customer,
            actor: @actor,
            reason: @reason,
          ).call
        else
          Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent.new(
            customer: customer,
            except_session_id: nil,
          ).call
        end
      end

      def close_auth_account(extid)
        return nil unless full_auth_mode?

        result = Auth::Operations::CloseAccount.call(
          extid: extid,
          db: @db,
          allow_missing: true,
          revoke_sessions: false,
          retain_account: true,
        )
        return result[:account_id] if result[:success]

        raise Onetime::Problem, "Unable to close auth account: #{result[:error]}"
      end

      def full_auth_mode?
        Onetime.auth_config.full_enabled?
      end
    end
  end
end
