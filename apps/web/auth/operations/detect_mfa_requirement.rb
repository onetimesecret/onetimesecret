# apps/web/auth/operations/detect_mfa_requirement.rb

#
# Detects whether multi-factor authentication is required for a login session.
# This operation encapsulates the logic for determining if:
# - MFA is enabled for the account
# - Session sync should be deferred until after MFA
#
# Returns a decision object with methods to query the MFA state.
#

module Auth
  module Operations
    # two_factor_partially_authenticated? :: (two_factor_base feature) Returns true if
    #                                        the session is logged in, the account has
    #                                        setup two factor authentication, but has
    #                                        not yet authenticated with a second factor.
    # uses_two_factor_authentication? :: (two_factor_base feature) Whether the account
    #                                    for the current session has setup two factor
    #                                    authentication.
    # update_last_activity :: (account_expiration feature) Update the last activity
    #                         time for the current account.  Only makes sense to use
    #                         this if you are expiring accounts based on last activity.
    class DetectMfaRequirement
      # Decision object returned by the operation
      class Decision
        attr_reader :account, :session, :mfa_enabled

        def initialize(account:, session:, mfa_enabled:)
          @account = account
          @session = session
          @mfa_enabled = mfa_enabled
        end

        # Does the account require MFA?
        # @return [Boolean]
        def requires_mfa?
          @mfa_enabled
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
        Decision.new(
          account: @account,
          session: @session,
          mfa_enabled: check_mfa_enabled,
        )
      end

      private

      # Checks if the account has MFA enabled
      # Uses Rodauth's built-in method to check if MFA is setup
      # @return [Boolean]
      def check_mfa_enabled
        has_mfa = @rodauth.uses_two_factor_authentication?

        # DEBUG: Log MFA check result
        Onetime.get_logger('Auth').debug "MFA check result",
          account_id: @account[:id],
          email: @account[:email],
          has_mfa: has_mfa,
          module: "DetectMfaRequirement"

        has_mfa
      end
    end
  end
end
