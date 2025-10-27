# apps/web/auth/operations/detect_mfa_requirement.rb

#
# Detects whether multi-factor authentication is required for a login session.
# This operation encapsulates the complex branching logic for determining if:
# - MFA is enabled for the account
# - MFA recovery mode is active
# - Session sync should be deferred until after MFA
#
# Returns a decision object with methods to query the MFA state.
#

module Auth
  module Operations
    class DetectMfaRequirement
      # Decision object returned by the operation
      class Decision
        attr_reader :account, :session, :recovery_mode, :mfa_enabled

        def initialize(account:, session:, recovery_mode:, mfa_enabled:)
          @account = account
          @session = session
          @recovery_mode = recovery_mode
          @mfa_enabled = mfa_enabled
        end

        # Is this a recovery mode request?
        # @return [Boolean]
        def recovery_mode?
          @recovery_mode
        end

        # Does the account require MFA?
        # @return [Boolean]
        def requires_mfa?
          @mfa_enabled && !@recovery_mode
        end

        # Should session sync be deferred until after MFA?
        # @return [Boolean]
        def defer_session_sync?
          requires_mfa?
        end

        # Should full session sync proceed immediately?
        # @return [Boolean]
        def sync_session_now?
          !requires_mfa?
        end

        # Get account ID
        # @return [Integer]
        def account_id
          @account[:id]
        end

        # Get account email
        # @return [String]
        def email
          @account[:email]
        end

        # Get external ID if present
        # @return [String, nil]
        def external_id
          @account[:external_id]
        end
      end

      # @param account [Hash] The Rodauth account hash
      # @param session [Hash] The Rack session
      # @param rodauth [Rodauth::Auth] The Rodauth instance (provides uses_two_factor_authentication?)
      def initialize(account:, session:, rodauth:)
        @account = account
        @session = session
        @rodauth = rodauth
      end

      # Convenience class method for direct calls
      # @param account [Hash] The Rodauth account hash
      # @param session [Hash] The Rack session
      # @param rodauth [Rodauth::Auth] The Rodauth instance
      # @return [Decision] The MFA decision object
      def self.call(account:, session:, rodauth:)
        new(account: account, session: session, rodauth: rodauth).call
      end

      # Executes the MFA detection operation
      # @return [Decision] The MFA decision object
      def call
        recovery_mode = detect_recovery_mode
        mfa_enabled = check_mfa_enabled

        Decision.new(
          account: @account,
          session: @session,
          recovery_mode: recovery_mode,
          mfa_enabled: mfa_enabled
        )
      end

      private

      # Detects if MFA recovery mode is active
      # @return [Boolean]
      def detect_recovery_mode
        @session[:mfa_recovery_mode] == true
      end

      # Checks if the account has MFA enabled
      # Uses Rodauth's built-in method to check if MFA is setup
      # @return [Boolean]
      def check_mfa_enabled
        @rodauth.uses_two_factor_authentication?
      end
    end
  end
end
