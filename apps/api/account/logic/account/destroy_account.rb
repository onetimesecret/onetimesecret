# apps/api/account/logic/account/destroy_account.rb
#
# frozen_string_literal: true

require 'onetime/logic/sso_only_gating'
require 'auth/operations/delete_account'

module AccountAPI::Logic
  module Account
    # Session-authenticated deletion endpoint retained for simple (Redis-only)
    # auth mode. Core's simple login writes the `authenticated` session marker
    # required by this route. The full-auth Settings UI uses Rodauth's
    # /auth/close-account route. Both endpoints delegate permanent teardown to
    # Auth::Operations::DeleteAccount.
    class DestroyAccount < AccountAPI::Logic::Base
      include Onetime::LoggerMethods
      include Onetime::Logic::SsoOnlyGating

      attr_reader :raised_concerns_was_called, :greenlighted

      def process_params
        return if params.nil?

        auth_logger.debug '[DestroyAccount#process_params] param keys', param_keys: params.keys.sort
        @confirmation = self.class.normalize_password(params['confirmation'])
      end

      def raise_concerns
        require_non_sso_only!

        @raised_concerns_was_called = true

        if @confirmation && @confirmation.empty?
          raise_form_error 'Password confirmation is required.', field: 'confirmation', error_type: 'required'
        else
          OT.info "[destroy-account] Passphrase check attempt cid/#{cust.objid} r/#{cust.role} ipa/#{session_sid}"

          raise_form_error 'Please check the password.', field: 'confirmation', error_type: 'incorrect' unless verify_password(@confirmation)
        end
      end

      def process
        # This is very defensive programming. When it comes to
        # destroying things though, let's pull out all the stops.
        raise_form_error 'We have concerns about that request.' unless raised_concerns_was_called

        return unless verify_password(@confirmation)

        # All criteria to destroy the account have been met.
        @greenlighted = true

        # Process the customer's request to destroy their account.
        # TODO: Limit to dev as well
        if Onetime.debug?
          cust.destroy_requested # not saved
          auth_logger.debug '[destroy-account] Simulated account destruction', extid: cust.extid, role: cust.role, session: session_sid

          # Debug mode simulates the action without modifying either account
          # store.
        else
          result = Auth::Operations::DeleteAccount.new(customer: cust).call
          unless result.status == :success
            raise_form_error 'Unable to delete account.', error_type: 'system_error'
          end

          OT.info "[destroy-account] Account destroyed. #{cust.objid} #{cust.role} #{session_sid}"
        end

        # Replace the session and session ID so the browser continues
        # with a fresh unauthenticated session.
        sess.clear

        success_data
      end

      def modified?(guess)
        modified.member? guess
      end

      def success_data
        { user_id: @cust.extid }
      end

      private

      # Verify password using the appropriate mechanism based on auth mode.
      # In full mode, password is stored in Rodauth's auth database.
      # In simple mode, password is stored in the Customer Redis model.
      #
      # @param password [String] The plaintext password to verify
      # @return [Boolean] true if the password matches
      def verify_password(password)
        return false if password.to_s.empty?

        if Onetime.auth_config.full_enabled?
          verify_password_full_mode(password)
        else
          cust.passphrase?(password)
        end
      end

      # Verify password against Rodauth's auth database (full mode).
      # Uses Rodauth's internal_request feature which handles argon2 secret,
      # password hash lookup, and verification internally.
      #
      # @param password [String] The plaintext password to verify
      # @return [Boolean] true if the password matches
      def verify_password_full_mode(password)
        Auth::Config.valid_login_and_password?(login: cust.email, password: password)
      rescue Rodauth::InternalRequestError => ex
        auth_logger.error '[destroy-account] Rodauth verification failed', exception: ex
        false
      rescue StandardError => ex
        auth_logger.error '[destroy-account] Password verification error', exception: ex
        false
      end
    end
  end
end
