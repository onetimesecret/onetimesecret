# apps/web/auth/config/rodauth_overrides.rb
#
# frozen_string_literal: true

module Auth::Config::RodauthOverrides
  # Placeholder for Rodauth overrides
  #
  def self.configure(auth)
    # SECURITY: Override verify_account's specific error messages with generic one
    # Prevents information disclosure about account existence/status
    # These methods are only available when verify_account feature is enabled
    #
    # We wrap these to log the actual error for debugging while showing generic message
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
          email: param('login'),
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
          email: param('login'),
          actual_error: actual_error,
          generic_error: 'Unable to create account',
        )
        'Unable to create account'
      end
    end
    # rubocop:enable Lint/NestedMethodDefinition
  end
end
