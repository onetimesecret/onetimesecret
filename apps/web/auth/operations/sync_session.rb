# apps/web/auth/operations/sync_session.rb

#
# Syncs the Rodauth session with the application's session format after
# successful authentication. This operation handles:
# - Clearing rate limiting
# - Creating or loading customer records
# - Populating session with user data
# - Linking Rodauth account to Customer model
#
# Idempotency protection ensures this operation can be safely retried:
# - Redis-based idempotency keys prevent double-execution
# - 5-minute TTL allows re-sync after timeout
# - Graceful degradation when Redis is unavailable
#

module Auth
  module Operations
    class SyncSession
      # Idempotency key TTL in seconds (5 minutes)
      IDEMPOTENCY_TTL = 300

      # @param account [Hash] The Rodauth account hash
      # @param account_id [Integer] The ID of the Rodauth account
      # @param session [Hash] The Rack session
      # @param request [Rack::Request] The request object
      # @param correlation_id [String] Optional correlation ID for tracking
      # @param db [Sequel::Database] The database connection (optional, uses Auth::Database if not provided)
      def initialize(account:, account_id:, session:, request:, correlation_id: nil, db: nil)
        @account = account
        @account_id = account_id
        @session = session
        @request = request
        @correlation_id = correlation_id || session[:auth_correlation_id]
        @db = db || Auth::Database.connection
      end

      # Convenience class method for direct calls
      # @param account [Hash] The Rodauth account hash
      # @param account_id [Integer] The ID of the Rodauth account
      # @param session [Hash] The Rack session
      # @param request [Rack::Request] The request object
      # @param correlation_id [String] Optional correlation ID for tracking
      # @param db [Sequel::Database] Optional database connection
      # @return [Onetime::Customer] The customer associated with this session
      def self.call(account:, account_id:, session:, request:, correlation_id: nil, db: nil)
        new(
          account: account,
          account_id: account_id,
          session: session,
          request: request,
          correlation_id: correlation_id,
          db: db
        ).call
      end

      # Executes the session sync operation with idempotency protection
      # @return [Onetime::Customer] The customer associated with this session
      def call
        Auth::Logging.log_operation(
          :session_sync_start,
          level: :info,
          account_id: @account_id,
          email: @account[:email],
          correlation_id: @correlation_id
        )

        # Check idempotency - skip if already processed
        if already_processed?
          Auth::Logging.log_operation(
            :session_sync_skipped,
            level: :info,
            account_id: @account_id,
            reason: 'already_processed',
            correlation_id: @correlation_id
          )
          return existing_customer
        end

        # Mark operation as in-progress
        mark_processing

        # Execute sync operation with compensation on failure
        customer = Auth::Logging.measure(
          :session_sync,
          account_id: @account_id,
          correlation_id: @correlation_id
        ) do
          begin
            clear_rate_limiting
            customer = ensure_customer_exists
            populate_session(customer)
            track_request_metadata
            customer
          rescue StandardError => ex
            # Compensation: clear idempotency key to allow retry
            clear_idempotency_key
            Auth::Logging.log_error(
              :session_sync_failed,
              exception: ex,
              account_id: @account_id,
              correlation_id: @correlation_id
            )
            raise
          end
        end

        Auth::Logging.log_operation(
          :session_sync_complete,
          level: :info,
          account_id: @account_id,
          email: @session['email'],
          customer_id: customer.custid,
          correlation_id: @correlation_id
        )

        customer
      end

      private

      # Clears rate limiting keys for this account
      def clear_rate_limiting
        rate_limit_key = "login_attempts:#{@account[:email]}"
        Familia.dbclient.del(rate_limit_key)
      end

      # Ensures a Customer record exists and is linked to the Rodauth account
      # @return [Onetime::Customer]
      def ensure_customer_exists
        customer = find_existing_customer || create_customer
        link_customer_to_account(customer) unless customer_linked?(customer)
        customer
      end

      # Finds existing customer by external_id or email
      # @return [Onetime::Customer, nil]
      def find_existing_customer
        customer = Onetime::Customer.find_by_extid(@account[:external_id]) if @account[:external_id]
        customer ||= Onetime::Customer.find_by_email(@account[:email])
        customer
      end

      # Creates a new customer from Rodauth account data
      # @return [Onetime::Customer]
      def create_customer
        Auth::Logging.log_operation(
          :customer_create_start,
          level: :info,
          email: @account[:email],
          correlation_id: @correlation_id
        )

        customer = Onetime::Customer.create!(
          email: @account[:email],
          role: 'customer',
          verified: rodauth_status_verified? ? '1' : '0'
        )

        Auth::Logging.log_operation(
          :customer_created,
          level: :info,
          customer_id: customer.custid,
          external_id: customer.extid,
          correlation_id: @correlation_id
        )
        customer
      end

      # Checks if the Rodauth account status is verified (status_id == 2)
      # @return [Boolean]
      def rodauth_status_verified?
        @account[:status_id] == 2
      end

      # Checks if customer is already linked to the Rodauth account
      # @return [Boolean]
      def customer_linked?(customer)
        @account[:external_id] == customer.extid
      end

      # Links the customer record to the Rodauth account via external_id
      # @param customer [Onetime::Customer]
      def link_customer_to_account(customer)
        @db[:accounts]
          .where(id: @account_id)
          .update(external_id: customer.extid)

        Auth::Logging.log_operation(
          :customer_linked,
          level: :info,
          customer_id: customer.custid,
          account_id: @account_id,
          correlation_id: @correlation_id
        )
      end

      # Populates the application session with user data
      # @param customer [Onetime::Customer]
      def populate_session(customer)
        @session['authenticated'] = true
        @session['authenticated_at'] = Familia.now.to_i
        @session['account_id'] = @account_id
        @session['external_id'] = customer.extid
        @session['email'] = customer.email
        @session['role'] = customer.role
        @session['locale'] = customer.locale || 'en'
      end

      # Tracks request metadata in the session
      def track_request_metadata
        @session['ip_address'] = @request.ip
        @session['user_agent'] = @request.user_agent
      end

      # Idempotency protection methods

      # Generates idempotency key for this sync operation
      # Key format: sync_session:account_id:session_id:timestamp_window
      # @return [String] The idempotency key
      def idempotency_key
        @idempotency_key ||= begin
          # Use session ID if available, otherwise use a stable identifier
          session_id = @session['session_id'] || @session.id rescue 'nosession'

          # Use 5-minute time window to allow re-sync after timeout
          timestamp_window = (Familia.now.to_i / IDEMPOTENCY_TTL).to_i

          "sync_session:#{@account_id}:#{session_id}:#{timestamp_window}"
        end
      end

      # Checks if this sync operation was already processed
      # @return [Boolean] true if already processed, false otherwise
      def already_processed?
        return false unless redis_available?

        exists = Familia.dbclient.exists?(idempotency_key)

        if exists == 1
          Auth::Logging.log_operation(
            :idempotency_check_hit,
            level: :debug,
            account_id: @account_id,
            idempotency_key: idempotency_key,
            correlation_id: @correlation_id
          )
          return true
        end

        false
      rescue Redis::BaseError => ex
        Auth::Logging.log_error(
          :idempotency_check_error,
          exception: ex,
          account_id: @account_id,
          correlation_id: @correlation_id
        )
        # Fail open - allow operation to proceed without idempotency protection
        false
      end

      # Marks operation as processing by setting idempotency key
      def mark_processing
        return unless redis_available?

        Familia.dbclient.setex(idempotency_key, IDEMPOTENCY_TTL, 'processing')
        Auth::Logging.log_operation(
          :idempotency_key_set,
          level: :debug,
          account_id: @account_id,
          idempotency_key: idempotency_key,
          ttl: IDEMPOTENCY_TTL,
          correlation_id: @correlation_id
        )
      rescue Redis::BaseError => ex
        Auth::Logging.log_error(
          :idempotency_key_set_error,
          exception: ex,
          account_id: @account_id,
          correlation_id: @correlation_id
        )
        # Continue without protection - logged for monitoring
      end

      # Clears idempotency key to allow retry after failure
      def clear_idempotency_key
        return unless redis_available?

        Familia.dbclient.del(idempotency_key)
        Auth::Logging.log_operation(
          :idempotency_key_cleared,
          level: :debug,
          account_id: @account_id,
          idempotency_key: idempotency_key,
          correlation_id: @correlation_id
        )
      rescue Redis::BaseError => ex
        Auth::Logging.log_error(
          :idempotency_key_clear_error,
          exception: ex,
          account_id: @account_id,
          correlation_id: @correlation_id
        )
        # Non-critical - key will expire naturally
      end

      # Returns existing customer record when operation already processed
      # @return [Onetime::Customer] The existing customer
      def existing_customer
        # If session already has external_id, use it to find customer
        if @session['external_id']
          customer = Onetime::Customer.find_by_extid(@session['external_id'])
          return customer if customer
        end

        # Fall back to finding by account linkage or email
        find_existing_customer || raise(OT::Problem, "Customer not found for already-processed sync")
      end

      # Checks if Redis is available for idempotency checks
      # @return [Boolean] true if Redis is available
      def redis_available?
        return @redis_available unless @redis_available.nil?

        @redis_available = begin
          Familia.dbclient&.ping == 'PONG'
        rescue Redis::BaseError, StandardError => ex
          Auth::Logging.log_error(
            :redis_unavailable,
            exception: ex,
            account_id: @account_id,
            correlation_id: @correlation_id
          )
          false
        end
      end
    end
  end
end
