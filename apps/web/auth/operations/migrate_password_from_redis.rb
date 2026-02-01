# apps/web/auth/operations/migrate_password_from_redis.rb
#
# frozen_string_literal: true

#
# Migrates a user's password from Redis (simple auth mode) to Rodauth (full mode).
#
# This operation is called during login when:
# 1. An account exists in the Rodauth database (accounts table)
# 2. No password hash exists in account_password_hashes table
# 3. A Customer record exists in Redis with a stored passphrase
#
# The operation verifies the provided password against the Redis Customer's
# passphrase (which may be bcrypt or argon2) and returns the result.
# The calling code (password_migration hook) handles creating the new
# Rodauth password hash on successful verification.
#
# Security considerations:
# - Uses Customer.passphrase? which has constant-time comparison
# - Does not expose password hashes or plaintext passwords
# - Logs attempts without sensitive data
# - Returns false for any unexpected errors (fail-secure)
#

module Auth
  module Operations
    class MigratePasswordFromRedis
      include Onetime::LoggerMethods

      # Result object for migration attempt
      MigrationResult = Struct.new(:success, :customer, :reason, keyword_init: true) do
        def success?
          success == true
        end

        def failed?
          !success?
        end
      end

      # @param email [String] The account email address
      # @param password [String] The plaintext password from login form
      def initialize(email:, password:)
        @email    = email
        @password = password
      end

      # Attempts to verify the password against the Redis Customer record.
      #
      # @return [MigrationResult] Result with success status and customer if found
      def call
        customer = find_customer
        return failure(:customer_not_found) unless customer
        return failure(:no_passphrase) unless customer.has_passphrase?

        if customer.passphrase?(@password)
          auth_logger.info '[password-migration] Redis password verified',
            {
              email: OT::Utils.obscure_email(@email),
              customer_id: customer.custid,
              encryption_type: customer.passphrase_encryption,
            }

          MigrationResult.new(
            success: true,
            customer: customer,
            reason: :verified,
          )
        else
          auth_logger.info '[password-migration] Redis password verification failed',
            {
              email: OT::Utils.obscure_email(@email),
              customer_id: customer.custid,
            }

          failure(:password_mismatch)
        end
      rescue StandardError => ex
        auth_logger.error '[password-migration] Unexpected error during migration',
          {
            email: OT::Utils.obscure_email(@email),
            error: ex.message,
            backtrace: ex.backtrace&.first(10)&.join("\n"),
          }

        failure(:error, ex.message)
      end

      private

      def find_customer
        return nil unless Onetime::Customer.email_exists?(@email)

        Onetime::Customer.find_by_email(@email)
      end

      def failure(reason, _details = nil)
        MigrationResult.new(
          success: false,
          customer: nil,
          reason: reason,
        )
      end
    end
  end
end
