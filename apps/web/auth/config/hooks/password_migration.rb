# apps/web/auth/config/hooks/password_migration.rb
#
# frozen_string_literal: true

#
# Password Migration Hook
#
# Enables transparent password migration from Redis (simple auth mode) to
# Rodauth (full auth mode) during login.
#
# When a user logs in and their account exists but has no password hash in
# the Rodauth database, this hook:
# 1. Verifies the password against the Redis Customer record
# 2. If valid, creates a new Rodauth password hash (argon2)
# 3. Returns true to allow login to proceed
#
# This allows gradual, zero-downtime migration from simple to full auth mode.
# After successful migration, subsequent logins use Rodauth directly.
#
# The hook only activates when:
# - An account exists in accounts table
# - No password hash exists in account_password_hashes
# - A Customer with passphrase exists in Redis
#

module Auth::Config::Hooks
  module PasswordMigration
    def self.configure(auth)
      #
      # Override: password_match?
      #
      # Rodauth calls this to verify passwords during login. We intercept
      # to check for password migration scenarios.
      #
      auth.include(InstanceMethods)

      auth.password_match? do |password|
        # Check if a password hash exists in Rodauth
        has_rodauth_password = begin
          # account_password_hash returns the hash if it exists, nil otherwise
          !get_password_hash.nil?
        rescue StandardError => ex
          Auth::Logging.log_auth_event(
            :password_hash_check_error,
            level: :error,
            email: OT::Utils.obscure_email(account[:email]),
            account_id: account_id,
            error: ex.message,
            backtrace: ex.backtrace&.first(10)&.join("\n"),
          )
          false
        end

        if has_rodauth_password
          # Normal Rodauth password verification (argon2)
          super(password)
        else
          # No Rodauth password - attempt migration from Redis
          migrate_password_from_redis(password)
        end
      end
    end

    # Registered as a Rodauth configuration method via the configure block
    module InstanceMethods
      private

      # Attempts to migrate password from Redis Customer to Rodauth.
      #
      # @param password [String] The plaintext password from login form
      # @return [Boolean] true if password verified and migration succeeded
      def migrate_password_from_redis(password)
        email = account[:email]

        Auth::Logging.log_auth_event(
          :password_migration_attempt,
          level: :info,
          email: OT::Utils.obscure_email(email),
          account_id: account_id,
        )

        # Verify password against Redis Customer
        result = Auth::Operations::MigratePasswordFromRedis.new(
          email: email,
          password: password,
        ).call

        unless result.success?
          Auth::Logging.log_auth_event(
            :password_migration_failed,
            level: :info,
            email: OT::Utils.obscure_email(email),
            account_id: account_id,
            reason: result.reason,
          )
          return false
        end

        # Password verified - create Rodauth password hash
        # This uses Rodauth's set_password which creates an argon2 hash
        begin
          set_password(password)

          Auth::Logging.log_auth_event(
            :password_migration_success,
            level: :info,
            email: OT::Utils.obscure_email(email),
            account_id: account_id,
            customer_id: result.customer.custid,
          )

          true
        rescue StandardError => ex
          Auth::Logging.log_auth_event(
            :password_migration_error,
            level: :error,
            email: OT::Utils.obscure_email(email),
            account_id: account_id,
            error: ex.message,
            backtrace: ex.backtrace&.first(10)&.join("\n"),
          )
          false
        end
      end
    end
  end
end
