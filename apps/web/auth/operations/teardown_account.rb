# apps/web/auth/operations/teardown_account.rb
#
# frozen_string_literal: true

require 'auth/operations/remove_authentication_data'
require 'auth/operations/destroy_customer_record'
require 'onetime/operations/sessions/revoke_all_for_customer'
require 'onetime/operations/sessions/revoke_all_for_customer_except_current'

module Auth
  module Operations
    # Permanently removes one account through the same ordered teardown in every
    # authentication mode and from both self-service and administrative callers.
    #
    # The operation revokes sessions first, closes the Rodauth identity and removes
    # its credentials when full auth is enabled, and deletes the Redis Customer
    # last. Rodauth invokes its after_close_account hook inside the SQL transaction;
    # that caller marks authentication_closed and keeps SQL closure committed after
    # any Redis mutation has started.
    #
    # Colonel auditing remains in Customers::Purge. Supplying actor selects the
    # audited administrative session-revocation operation; self-service callers do
    # not write to the Colonel audit trail.
    #
    # `sweep_untracked_sessions: false` skips the administrative revocation's
    # keyspace walk for pre-sidecar blobs (see RevokeAllForCustomer): a bulk
    # sweep of long-idle accounts has nothing for it to find and would repeat
    # the walk once per account. The tracked revocation always runs.
    class TeardownAccount
      class Result
        attr_reader :status, :extid, :custid, :account_id, :completed_stages, :blocked_stage

        def initialize(status:, extid:, custid:, account_id:, completed_stages: [], blocked_stage: nil)
          @status           = status
          @extid            = extid
          @custid           = custid
          @account_id       = account_id
          @completed_stages = completed_stages.freeze
          @blocked_stage    = blocked_stage
          freeze
        end
      end

      def initialize(customer: nil, account: nil, actor: nil, reason: nil, db: nil,
                     before_mutation: nil, on_mutation: nil, authentication_closed: false,
                     bulk_audit_context: nil, sweep_untracked_sessions: true)
        raise ArgumentError, 'Must provide either customer: or account:' if customer.nil? && account.nil?
        raise ArgumentError, 'Cannot provide both customer: and account:' if customer && account

        @customer                 = customer
        @account                  = account
        @actor                    = actor
        @reason                   = reason
        @db                       = db
        @before_mutation          = before_mutation
        @on_mutation              = on_mutation
        @authentication_closed    = authentication_closed
        @bulk_audit_context       = bulk_audit_context
        @sweep_untracked_sessions = sweep_untracked_sessions
        @completed_stages         = []
      end

      # rubocop:disable Metrics/PerceivedComplexity -- two stores, one irreversible
      # ordering; the branches are the cross-store outcome matrix
      def call
        customer = @customer || find_customer
        unless customer
          account_id = @authentication_closed ? @account&.[](:id) : close_auth_account(account_extid)
          status     = @account && full_auth_mode? ? :success : :not_found
          return Result.new(
            status: status,
            extid: account_extid,
            custid: nil,
            account_id: account_id,
            completed_stages: @completed_stages,
          )
        end

        extid  = customer.extid
        custid = customer.custid

        return blocked_result(:session_revocation, extid, custid) unless mutation_allowed?(:session_revocation)

        mutation_started!(:session_revocation)
        revoke_sessions(customer)
        @completed_stages << :session_revocation

        if full_auth_mode? && !@authentication_closed && !mutation_allowed?(:authentication_closure)
          return blocked_result(:authentication_closure, extid, custid)
        end

        mutation_started!(:authentication_closure) if full_auth_mode? && !@authentication_closed
        account_id = if @authentication_closed
                       @account&.[](:id)
                     else
                       close_auth_account(extid)
                     end
        @completed_stages << :authentication_closure if full_auth_mode? && !@authentication_closed

        return blocked_result(:customer_deletion, extid, custid, account_id) unless mutation_allowed?(:customer_deletion)

        mutation_started!(:customer_deletion)
        deleted = Auth::Operations::DestroyCustomerRecord.new(customer: customer).call
        @completed_stages << :customer_deletion if deleted

        status = if deleted
                   :success
                 elsif @before_mutation && @completed_stages.any?
                   :partial
                 else
                   :not_found
                 end
        Result.new(
          status: status,
          extid: extid,
          custid: custid,
          account_id: account_id,
          completed_stages: @completed_stages,
        )
      end
      # rubocop:enable Metrics/PerceivedComplexity

      private

      def mutation_started!(stage)
        @on_mutation&.call(stage)
      end

      def mutation_allowed?(stage)
        return true unless @before_mutation

        @before_mutation.call(stage) == true
      end

      def blocked_result(stage, extid, custid, account_id = nil)
        status = @completed_stages.empty? ? :refused : :partial
        Result.new(
          status: status,
          extid: extid,
          custid: custid,
          account_id: account_id,
          completed_stages: @completed_stages,
          blocked_stage: stage,
        )
      end

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
            bulk_audit_context: @bulk_audit_context,
            sweep_untracked: @sweep_untracked_sessions,
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

        result = Auth::Operations::RemoveAuthenticationData.call(
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
