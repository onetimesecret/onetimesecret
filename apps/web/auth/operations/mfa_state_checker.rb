# apps/web/auth/operations/mfa_state_checker.rb
#
# frozen_string_literal: true

#
# Service for checking MFA (Multi-Factor Authentication) configuration state
# from the database. This provides a secure, isolated way to verify MFA setup
# without depending on Rodauth internals or session state.
#
# Security Principles:
# - Direct database queries (no implicit trust)
# - Minimal data exposure (returns only boolean states)
# - Cacheable results (optional TTL to reduce DB load)
# - Auditable (structured logging)
#
# Example:
#   checker = Auth::Operations::MfaStateChecker.new(DB)
#   state = checker.check(account_id: 123)
#   if state.has_otp_secret
#     # Account has OTP configured
#   end
#

module Auth
  module Operations
    class MfaStateChecker
      # State object returned by the checker
      class State
        attr_reader :account_id, :has_otp_secret, :has_recovery_codes,
          :otp_last_use, :unused_recovery_code_count

        def initialize(
          account_id:,
          has_otp_secret:,
          has_recovery_codes:,
          otp_last_use: nil,
          unused_recovery_code_count: 0
        )
          @account_id                 = account_id
          @has_otp_secret             = has_otp_secret
          @has_recovery_codes         = has_recovery_codes
          @otp_last_use               = otp_last_use
          @unused_recovery_code_count = unused_recovery_code_count

          freeze # Immutable
        end

        # Does the account have ANY form of MFA configured?
        # @return [Boolean]
        def mfa_enabled?
          has_otp_secret || has_recovery_codes
        end

        # Get list of available MFA methods
        # @return [Array<Symbol>] Array of :otp, :recovery_codes, or empty
        def available_methods
          methods = []
          methods << :otp if has_otp_secret
          methods << :recovery_codes if has_recovery_codes
          methods.freeze
        end

        # Get a reason string for why MFA is or isn't required
        # @return [String]
        def reason
          return 'no_mfa_configured' unless mfa_enabled?

          if has_otp_secret && has_recovery_codes
            'otp_and_recovery_configured'
          elsif has_otp_secret
            'otp_configured'
          elsif has_recovery_codes
            'recovery_codes_only'
          end
        end
      end

      # @param db [Sequel::Database] The database connection
      # @param logger [Logger, nil] Optional logger for audit trail
      # @param cache_ttl [Integer, nil] Optional cache TTL in seconds (nil = no cache)
      def initialize(db, logger: nil, cache_ttl: nil)
        @db        = db
        @logger    = logger || Onetime.get_logger('Auth::MfaStateChecker')
        @cache_ttl = cache_ttl
        @cache     = {} if cache_ttl
      end

      # Check MFA state for an account
      # @param account_id [Integer, String] The account ID
      # @return [State] The MFA state object
      def check(account_id)
        account_id = account_id.to_i

        # Check cache if enabled
        if @cache_ttl && (cached = get_from_cache(account_id))
          @logger.debug 'MFA state cache hit',
            account_id: account_id,
            module: 'MfaStateChecker'
          return cached
        end

        # Query database for MFA configuration
        state = query_mfa_state(account_id)

        # Store in cache if enabled
        store_in_cache(account_id, state) if @cache_ttl

        @logger.debug 'MFA state checked',
          account_id: account_id,
          has_otp: state.has_otp_secret,
          has_recovery: state.has_recovery_codes,
          mfa_enabled: state.mfa_enabled?,
          module: 'MfaStateChecker'

        state
      end

      # Clear cache for specific account (useful after MFA setup/removal)
      # @param account_id [Integer, String] The account ID
      def clear_cache(account_id = nil)
        return unless @cache

        if account_id
          @cache.delete(cache_key(account_id.to_i))
        else
          @cache.clear
        end
      end

      private

      # Query the database for MFA state
      # @param account_id [Integer] The account ID
      # @return [State] The MFA state object
      def query_mfa_state(account_id)
        # Check for OTP secret
        # Note: account_otp_keys.id is the account_id (FK to accounts table)
        otp_record = @db[:account_otp_keys]
          .where(id: account_id)
          .select(:last_use)
          .first

        has_otp_secret = !otp_record.nil?
        otp_last_use   = otp_record&.fetch(:last_use, nil)

        # Check for unused recovery codes
        # Note: account_recovery_codes.id is ALSO the FK to accounts table (composite PK: id, code)
        # The table does NOT have a used_at column - codes are deleted when used
        unused_codes_count = @db[:account_recovery_codes]
          .where(id: account_id)
          .count

        has_recovery_codes = unused_codes_count > 0

        State.new(
          account_id: account_id,
          has_otp_secret: has_otp_secret,
          has_recovery_codes: has_recovery_codes,
          otp_last_use: otp_last_use,
          unused_recovery_code_count: unused_codes_count,
        )
      end

      # Get state from cache
      # @param account_id [Integer] The account ID
      # @return [State, nil] Cached state or nil if expired/not found
      def get_from_cache(account_id)
        key   = cache_key(account_id)
        entry = @cache[key]

        return nil unless entry

        # Check expiration
        if Time.now.to_i - entry[:timestamp] > @cache_ttl
          @cache.delete(key)
          return nil
        end

        entry[:state]
      end

      # Store state in cache
      # @param account_id [Integer] The account ID
      # @param state [State] The state to cache
      def store_in_cache(account_id, state)
        @cache[cache_key(account_id)] = {
          state: state,
          timestamp: Time.now.to_i,
        }
      end

      # Generate cache key
      # @param account_id [Integer] The account ID
      # @return [String] Cache key
      def cache_key(account_id)
        "mfa_state:#{account_id}"
      end
    end
  end
end
