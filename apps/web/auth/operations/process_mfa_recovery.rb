# apps/web/auth/operations/process_mfa_recovery.rb

#
# Processes MFA recovery flow when a user authenticates via email link
# because they can't access their authenticator app.
#
# This operation:
# - Disables OTP authentication for the account
# - Removes all recovery codes
# - Clears MFA recovery session flags
# - Sets completion flag for frontend notification
#
# SECURITY NOTE: This should only execute when session[:mfa_recovery_mode] is true,
# which is set by the email authentication flow specifically for MFA recovery.
#

module Auth
  module Operations
    class ProcessMfaRecovery
      # @param account [Hash] The Rodauth account hash
      # @param account_id [Integer] The ID of the Rodauth account
      # @param session [Hash] The Rack session
      # @param rodauth [Rodauth::Auth] The Rodauth instance (provides OTP methods)
      # @param db [Sequel::Database] The database connection (optional)
      def initialize(account:, account_id:, session:, rodauth:, db: nil)
        @account = account
        @account_id = account_id
        @session = session
        @rodauth = rodauth
        @db = db || Auth::Database.connection
      end

      # Convenience class method for direct calls
      # @param account [Hash] The Rodauth account hash
      # @param account_id [Integer] The ID of the Rodauth account
      # @param session [Hash] The Rack session
      # @param rodauth [Rodauth::Auth] The Rodauth instance
      # @param db [Sequel::Database] Optional database connection
      # @return [Boolean] true if recovery was processed successfully
      def self.call(account:, account_id:, session:, rodauth:, db: nil)
        new(
          account: account,
          account_id: account_id,
          session: session,
          rodauth: rodauth,
          db: db
        ).call
      end

      # Executes the MFA recovery operation
      # @return [Boolean] true if recovery was processed successfully
      def call
        log_recovery_initiation

        # Disable MFA with error handling
        Onetime::ErrorHandler.safe_execute('mfa_recovery_disable_otp',
          account_id: @account_id,
          email: @account[:email]
        ) do
          disable_otp_authentication
          disable_recovery_codes
        end

        # Update session flags and log completion
        update_session_flags
        log_recovery_completion

        true
      end

      private

      # Logs the initiation of MFA recovery
      def log_recovery_initiation
        SemanticLogger['Auth'].warn 'MFA recovery initiated via email auth',
          account_id: @account[:id],
          email: @account[:email]
      end

      # Disables OTP authentication for the account
      def disable_otp_authentication
        # Remove OTP authentication failures tracking
        @rodauth._otp_remove_auth_failures if @rodauth.respond_to?(:_otp_remove_auth_failures)

        # Remove OTP key from database
        @rodauth._otp_remove_key(@account_id) if @rodauth.respond_to?(:_otp_remove_key)
      end

      # Removes all recovery codes from the database
      def disable_recovery_codes
        return unless recovery_codes_table_defined?

        @db[recovery_codes_table]
          .where(recovery_codes_id_column => @account_id)
          .delete
      end

      # Checks if recovery codes table is defined in Rodauth config
      # @return [Boolean]
      def recovery_codes_table_defined?
        defined?(recovery_codes_table) && @rodauth.respond_to?(:recovery_codes_table)
      end

      # Gets the recovery codes table name from Rodauth
      # @return [Symbol]
      def recovery_codes_table
        @rodauth.recovery_codes_table
      end

      # Gets the recovery codes ID column from Rodauth
      # @return [Symbol]
      def recovery_codes_id_column
        @rodauth.recovery_codes_id_column
      end

      # Updates session flags after successful recovery
      def update_session_flags
        # Clear recovery mode flag
        @session.delete(:mfa_recovery_mode)

        # Set flag for frontend notification
        @session[:mfa_recovery_completed] = true
      end

      # Logs successful recovery completion
      def log_recovery_completion
        SemanticLogger['Auth'].info 'MFA disabled via recovery flow',
          account_id: @account_id,
          email: @account[:email]
      end
    end
  end
end
