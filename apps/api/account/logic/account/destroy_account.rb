# apps/api/account/logic/account/destroy_account.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Account
    class DestroyAccount < AccountAPI::Logic::Base
      attr_reader :raised_concerns_was_called, :greenlighted

      def process_params
        return if params.nil?

        OT.ld "[DestroyAccount#process_params] param keys: #{params.keys.sort}"
        @confirmation = self.class.normalize_password(params['confirmation'])
      end

      def raise_concerns
        @raised_concerns_was_called = true

        if @confirmation&.empty?
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
          OT.ld "[destroy-account] Simulated account destruction #{cust.objid} #{cust.role} #{session_sid}"

          # Since we intentionally don't call Customer#destroy_requested!
          # when running in debug mode (to simulate the destruction but
          # not actually modify the customer record), the tryouts that
          # checked the state of the customer record after destroying
          # will fail (e.g. they expect the passphrase to be removed).

          # We add a message to the session to let the debug user know
          # that we made it to this point in the logic. Otherwise, they
          # might not know if the action was successful or not since we
          # don't actually destroy the account in debug mode.
          set_info_message('Account deleted')

        else
          # In full auth mode, delete from auth database FIRST.
          # This ensures that if the PostgreSQL deletion fails, we don't leave
          # the system in an inconsistent state with a "deleted" Redis record
          # but an active auth account.
          if Onetime.auth_config.full_enabled?
            result = delete_auth_account(cust)
            unless result[:success]
              raise_form_error "Unable to delete account: #{result[:error]}", error_type: 'system_error'
            end
          end

          # Now mark the customer record as deleted in Redis
          cust.destroy_requested!

          # Log the event immediately after saving the change to
          # to minimize the chance of the event not being logged.
          OT.info "[destroy-account] Account destroyed. #{cust.objid} #{cust.role} #{session_sid}"
        end

        # We replace the session and session ID and then add a message
        # for the user so that when the page they're directed to loads
        # (i.e. the homepage), they'll see it and remember what they did.
        sess.clear
        set_info_message('Account deleted')

        success_data
      end

      def modified?(guess)
        modified.member? guess
      end

      def success_data
        { user_id: @cust.objid }
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
        OT.le "[destroy-account] Rodauth verification failed: #{ex.message}"
        false
      rescue StandardError => ex
        OT.le "[destroy-account] Password verification error: #{ex.message}"
        OT.ld ex.backtrace.first(5).join("\n")
        false
      end

      # Delete account and all related data from auth database in full mode.
      # Uses Auth::Operations::CloseAccount which handles all dependent tables
      # within a transaction.
      #
      # @param customer [Onetime::Customer]
      # @return [Hash] Result with :success and optionally :error
      def delete_auth_account(customer)
        return { success: false, error: 'Customer extid is required' } unless customer&.extid

        Auth::Operations::CloseAccount.call(extid: customer.extid)
      end
    end
  end
end
