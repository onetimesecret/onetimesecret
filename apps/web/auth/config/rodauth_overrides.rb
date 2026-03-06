# apps/web/auth/config/rodauth_overrides.rb
#
# frozen_string_literal: true

require 'digest'

module Auth::Config::RodauthOverrides
  # Rodauth method overrides for security and logging
  #
  def self.configure(auth)
    # SECURITY: Override verify_account's specific error messages with generic one
    # Prevents information disclosure about account existence/status
    # These methods are only available when verify_account feature is enabled
    #
    # We wrap these to log the actual error for debugging while showing generic message
    auth_class = auth.instance_variable_get(:@auth)
    return unless auth_class&.features&.include?(:verify_account)

    # rubocop:disable Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
    auth.auth_class_eval do
      # Store original methods
      alias_method :_original_attempt_to_create_unverified_account_error_flash,
        :attempt_to_create_unverified_account_error_flash
      alias_method :_original_attempt_to_login_to_unverified_account_error_flash,
        :attempt_to_login_to_unverified_account_error_flash

      # Override to log actual error before returning generic message
      def attempt_to_create_unverified_account_error_flash
        actual_error = _original_attempt_to_create_unverified_account_error_flash
        Auth::Logging.log_auth_event(
          :create_account_blocked,
          level: :warn,
          email_hash: Digest::SHA256.hexdigest(param('login').to_s.downcase)[0..7],
          actual_error: actual_error,
          generic_error: 'Unable to create account',
        )
        'Unable to create account'
      end

      def attempt_to_login_to_unverified_account_error_flash
        actual_error = _original_attempt_to_login_to_unverified_account_error_flash
        Auth::Logging.log_auth_event(
          :login_blocked_unverified,
          level: :warn,
          email_hash: Digest::SHA256.hexdigest(param('login').to_s.downcase)[0..7],
          actual_error: actual_error,
          generic_error: 'Unable to authenticate account',
        )
        'Unable to authenticate account'
      end
    end
    # rubocop:enable Lint/NestedMethodDefinition
  end
end
