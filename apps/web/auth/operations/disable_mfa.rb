# apps/web/auth/operations/disable_mfa.rb

#
# Disables multi-factor authentication for a customer account.
# This operation removes all MFA setup including OTP keys and recovery codes.
#
# SECURITY NOTE: This should ONLY be used in console sessions for account
# recovery purposes, never exposed via API endpoints or web routes.
#
# Usage in console:
#   Auth::Operations::DisableMfa.new(email: 'user@example.com').call
#
# Or via the convenience class method:
#   Auth::Operations::DisableMfa.call('user@example.com')
#

module Auth
  module Operations
    class DisableMfa
      # @param email [String] The customer's email address
      # @param db [Sequel::Database] The database connection (optional)
      def initialize(email:, db: nil)
        @email = email
        @db = db || Auth::Database.connection
      end

      # Executes the MFA disable operation
      # @return [Boolean] true if MFA was disabled, false otherwise
      def call
        return false unless validate_customer
        return false unless validate_account
        return false unless mfa_enabled?

        disable_otp_authentication
        disable_recovery_codes

        log_success
        true
      rescue => e
        log_error(e)
        false
      end

      # Convenience class method for direct calls
      # Forwards all arguments to new instance
      # @return [Boolean] true if MFA was disabled
      def self.call(*, **)
        new(*, **).call
      end

      private

      # Validates that the customer exists
      # @return [Boolean]
      def validate_customer
        @customer = Onetime::Customer.find_by_email(@email)

        unless @customer
          puts "❌ Customer not found: #{@email}"
          return false
        end

        true
      end

      # Validates that an active Rodauth account exists
      # @return [Boolean]
      def validate_account
        @account = @db[:accounts].where(email: @email, status_id: 2).first

        unless @account
          puts "❌ Active account not found for: #{@email}"
          return false
        end

        @account_id = @account[:id]
        true
      end

      # Checks if MFA is enabled for this account
      # @return [Boolean]
      def mfa_enabled?
        @otp_key_exists = @db[:account_otp_keys].where(account_id: @account_id).count > 0
        @recovery_codes_exist = @db[:account_recovery_codes].where(account_id: @account_id).count > 0

        unless @otp_key_exists || @recovery_codes_exist
          puts "ℹ️  No MFA setup found for: #{@email}"
          return false
        end

        true
      end

      # Removes OTP keys from the database
      def disable_otp_authentication
        return unless @otp_key_exists

        @db[:account_otp_keys].where(account_id: @account_id).delete
        puts "✅ Removed OTP key for: #{@email}"
      end

      # Removes all recovery codes from the database
      def disable_recovery_codes
        return unless @recovery_codes_exist

        codes_removed = @db[:account_recovery_codes].where(account_id: @account_id).delete
        puts "✅ Removed #{codes_removed} recovery code(s) for: #{@email}"
      end

      # Logs successful operation
      def log_success
        puts "✅ MFA successfully disabled for: #{@email}"
        puts "⚠️  User should re-enable MFA from account settings after login"

        OT.info "[disable-mfa] MFA disabled for account",
          email: OT::Utils.obscure_email(@email),
          account_id: @account_id,
          customer_id: @customer.custid
      end

      # Logs error information
      # @param error [Exception]
      def log_error(error)
        puts "❌ Error disabling MFA: #{error.message}"
        puts error.backtrace.first(5).join("\n")

        OT.error "[disable-mfa] Failed to disable MFA",
          email: OT::Utils.obscure_email(@email),
          error: error.message
      end
    end
  end
end
