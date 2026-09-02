# apps/web/auth/operations/sync_session.rb
#
# frozen_string_literal: true

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
# Also the full-auth-mode site for the colonel.signin audit event — see
# #record_colonel_signin.
#

require 'onetime/models/colonel_audit_event'

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
        @account        = account
        @account_id     = account_id
        @session        = session
        @request        = request
        @correlation_id = correlation_id || session[:auth_correlation_id]
        @db             = db || Auth::Database.connection
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
          db: db,
        ).call
      end

      # Executes the session sync operation with idempotency protection
      # @return [Onetime::Customer] The customer associated with this session
      def call
        Auth::Logging.log_operation(
          :session_sync_start,
          level: :info,
          account_id: @account_id,
          external_id: @account[:external_id],
          correlation_id: @correlation_id,
        )

        # Check idempotency - skip if already processed
        if already_processed?
          Auth::Logging.log_operation(
            :session_sync_skipped,
            level: :info,
            account_id: @account_id,
            reason: 'already_processed',
            correlation_id: @correlation_id,
          )
          return existing_customer
        end

        # Mark operation as in-progress
        mark_processing

        # Execute sync operation with compensation on failure
        customer = Auth::Logging.measure(
          :session_sync,
          account_id: @account_id,
          correlation_id: @correlation_id,
        ) do
            clear_rate_limiting
            customer = ensure_customer_exists
            populate_session(customer)
            stamp_last_login(customer)
            track_request_metadata
            customer
        rescue StandardError => ex
            # Compensation: clear idempotency key to allow retry
            clear_idempotency_key
            Auth::Logging.log_error(
              :session_sync_failed,
              exception: ex,
              account_id: @account_id,
              correlation_id: @correlation_id,
            )
            raise
        end

        Auth::Logging.log_operation(
          :session_sync_complete,
          level: :info,
          account_id: @account_id,
          email: @session['email'],
          customer_id: customer.custid,
          correlation_id: @correlation_id,
        )

        record_colonel_signin(customer)

        customer
      end

      private

      # Record a colonel.signin event when the session just established belongs
      # to a colonel.
      #
      # ## Why this exists
      #
      # Nearly all colonel activity is reads, and reads never audit by design
      # (CONTRACT 4), so a quiet week leaves the audit screen looking empty even
      # while operators are in the console daily. Session establishment is the
      # one honest signal of operator PRESENCE, as opposed to operator writes.
      #
      # ## Success only — here
      #
      # A failed login never reaches this op, and must not: the operator trail
      # is capped by COUNT with no TTL, so an event an unauthenticated caller
      # can trigger would be a log-eviction primitive against it — enough failed
      # logins would flush the real destructive-action trail. That argument is
      # about `events`, and it is why THIS write stays a `.record`.
      #
      # It is no longer a reason for failures to record NOTHING (#4339). They
      # are audited at the Rodauth login-failure hook instead
      # (Auth::Config::Hooks::Login → Onetime::ColonelSigninFailure), into the
      # separate `security_events` collection, where a flood can only ever
      # evict other anonymous telemetry.
      #
      # ## Exactly once per login
      #
      # This is a per-SESSION site, not a per-request one. SyncSession is called
      # from after_login (the no-MFA branch) or from
      # after_two_factor_authentication — mutually exclusive, one per completed
      # login. It also sits BELOW the already_processed? early return, so it
      # inherits the idempotency guard: a re-entrant sync inside the 5-minute
      # window returns early and never reaches here.
      #
      # Simple auth mode does not run Rodauth at all; its equivalent site is
      # Core::Logic::Authentication::AuthenticateSession#process.
      def record_colonel_signin(customer)
        return unless customer.role.to_s == 'colonel'

        Onetime::ColonelAuditEvent.record(
          actor: customer.extid,
          verb: Onetime::ColonelAuditEvent::VERB_COLONEL_SIGNIN,
          target: customer.extid,
          result: :success,
          detail: {
            auth_method: @session['auth_method'],
            ip: (@request.ip if @request.respond_to?(:ip)),
          },
        )
      rescue StandardError => ex
        # Best-effort, like every other audit write: a login must never fail
        # because its audit event could not be assembled.
        Auth::Logging.log_error(
          :colonel_signin_audit_failed,
          exception: ex,
          account_id: @account_id,
          correlation_id: @correlation_id,
        )
      end

      # Clears rate limiting keys for this account
      def clear_rate_limiting
        rate_limit_key = "login_attempts:#{@account[:email].to_s.downcase}"
        Familia.dbclient.del(rate_limit_key)
      end

      # Ensures a Customer record exists and is linked to the Rodauth account.
      # Handles race condition where OmniAuth callback just created the customer
      # but the email index lookup misses it (Familia index timing).
      # @return [Onetime::Customer]
      def ensure_customer_exists
        customer   = find_existing_customer
        customer ||= begin
          create_customer
        rescue Familia::RecordExistsError
          # Customer was just created (likely by OmniAuth callback) but index
          # lookup missed it. Retry briefly since index should converge.
          # NOTE: Polling because Redis has no "wait until hash field exists"
          # primitive; index lag is sub-ms in practice, this is a safety net.
          retried_customer = nil
          3.times do
            retried_customer = Onetime::Customer.find_by_email(@account[:email])
            break if retried_customer

            sleep 0.05
          end
          retried_customer || raise(OT::Problem, "Customer index sync failed for #{@account[:email]}")
        end
        link_customer_to_account(customer) unless customer_linked?(customer)
        customer
      end

      # Finds existing customer by external_id or email
      # @return [Onetime::Customer, nil]
      def find_existing_customer
        customer   = Onetime::Customer.find_by_extid(@account[:external_id]) if @account[:external_id]
        customer ||= Onetime::Customer.find_by_email(@account[:email])
        customer
      end

      # Creates a new customer from Rodauth account data
      # @return [Onetime::Customer]
      def create_customer
        # New accounts default to 'customer' role. Colonel promotion
        # is handled exclusively via CLI: bin/ots customers role promote user@example.com
        Auth::Logging.log_operation(
          :customer_create_start,
          level: :info,
          email: @account[:email],
          role: 'customer',
          correlation_id: @correlation_id,
        )

        customer = Onetime::Customer.create!(
          email: @account[:email],
          role: 'customer',
        )

        # Persist verification state via Familia's single-field fast writer.
        # The Customer model coerces this to canonical 'true'/'false' (see
        # Customer::Features::Status) so the value matches what `verified?`
        # checks against.
        customer.verified!(rodauth_status_verified?)

        Auth::Logging.log_operation(
          :customer_created,
          level: :info,
          customer_id: customer.custid,
          external_id: customer.extid,
          role: 'customer',
          correlation_id: @correlation_id,
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
          correlation_id: @correlation_id,
        )
      end

      # Populates the application session with user data
      # @param customer [Onetime::Customer]
      def populate_session(customer)
        @session['authenticated']    = true
        @session['authenticated_at'] = Familia.now.to_i
        @session['account_id']       = @account_id
        @session['external_id']      = customer.extid
        @session['email']            = customer.email
        @session['role']             = customer.role
        @session['locale']           = customer.locale || 'en'

        # Clear MFA waiting flag - user has completed full authentication
        @session.delete(:awaiting_mfa)
        @session.delete('awaiting_mfa')

        # #4327: an identity change must always land UNELEVATED. Rodauth's
        # :renew carries the session hash to a new sid (hooks/account.rb after a
        # password change), so a colonel step-up window could otherwise survive
        # a rotation — or an identity change — on the same browser. Elevation is
        # also identity-bound on read; this is the second of two closures.
        @session.delete('elevated_until')
      end

      # Stamps the customer's last_login timestamp on full session sync.
      #
      # last_login is not maintained by Rodauth — the authoritative login
      # activity lives in the auth database (account_activity_times). We mirror
      # it onto the Customer here, on the post-authentication (post-MFA) sync,
      # so the colonel console can show it without reaching into authdb per row.
      #
      # Uses the single-field fast writer (HSET of just last_login) to avoid a
      # full object save, and is best-effort: a write failure must never abort
      # an otherwise-successful login, so it is logged and swallowed rather than
      # allowed to trip the surrounding rescue-and-reraise.
      #
      # @param customer [Onetime::Customer]
      def stamp_last_login(customer)
        customer.last_login!(Familia.now.to_f)
      rescue StandardError => ex
        Auth::Logging.log_error(
          :last_login_stamp_failed,
          exception: ex,
          account_id: @account_id,
          correlation_id: @correlation_id,
        )
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
          # Use session ID if available, otherwise generate unique ID to prevent collisions
          session_id = @session['session_id'] || begin
                                                   @session.id
          rescue StandardError
                                                   SecureRandom.hex(16)
          end

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
            correlation_id: @correlation_id,
          )
          return true
        end

        false
      rescue Redis::BaseError => ex
        Auth::Logging.log_error(
          :idempotency_check_error,
          exception: ex,
          account_id: @account_id,
          correlation_id: @correlation_id,
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
          correlation_id: @correlation_id,
        )
      rescue Redis::BaseError => ex
        Auth::Logging.log_error(
          :idempotency_key_set_error,
          exception: ex,
          account_id: @account_id,
          correlation_id: @correlation_id,
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
          correlation_id: @correlation_id,
        )
      rescue Redis::BaseError => ex
        Auth::Logging.log_error(
          :idempotency_key_clear_error,
          exception: ex,
          account_id: @account_id,
          correlation_id: @correlation_id,
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
        find_existing_customer || raise(OT::Problem, 'Customer not found for already-processed sync')
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
            correlation_id: @correlation_id,
          )
          false
        end
      end
    end
  end
end
