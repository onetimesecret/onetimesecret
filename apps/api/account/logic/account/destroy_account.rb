# apps/api/account/logic/account/destroy_account.rb
#
# frozen_string_literal: true

require 'argon2'

module AccountAPI::Logic
  module Account
    class DestroyAccount < AccountAPI::Logic::Base
      attr_reader :raised_concerns_was_called, :greenlighted

      def process_params
        return if params.nil?

        OT.ld "[DestroyAccount#process_params] params: #{params.inspect}"
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
          cust.destroy_requested!

          # Log the event immediately after saving the change to
          # to minimize the chance of the event not being logged.
          OT.info "[destroy-account] Account destroyed. #{cust.objid} #{cust.role} #{session_sid}"

          # If in full mode, also delete from auth database
          delete_auth_account(cust) if Onetime.auth_config.full_enabled?
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
        if Onetime.auth_config.full_enabled?
          verify_password_full_mode(password)
        else
          cust.passphrase?(password)
        end
      end

      # Verify password against Rodauth's auth database (full mode).
      # Looks up the account by extid and verifies against the password hash.
      #
      # @param password [String] The plaintext password to verify
      # @return [Boolean] true if the password matches
      def verify_password_full_mode(password)
        db = Auth::Database.connection
        return false unless db

        # Find the account by external_id (which maps to Customer#extid)
        account = db[:accounts].where(external_id: cust.extid).first
        return false unless account

        # Get the password hash for this account
        password_hash_row = db[:account_password_hashes].where(id: account[:id]).first
        return false unless password_hash_row

        stored_hash = password_hash_row[:password_hash]
        return false if stored_hash.to_s.empty?

        # Verify using Argon2 (same as Rodauth uses)
        ::Argon2::Password.verify_password(password, stored_hash)
      rescue ::Argon2::ArgonHashFail => ex
        OT.le "[destroy-account] Argon2 verification failed: #{ex.message}"
        false
      rescue StandardError => ex
        OT.le "[destroy-account] Password verification error: #{ex.message}"
        OT.ld ex.backtrace.first(5).join("\n")
        false
      end

      # Delete account from auth database in full mode
      # @param customer [Onetime::Customer]
      def delete_auth_account(customer)
        return unless customer&.extid

        db = Auth::Database.connection
        return unless db

        deleted = db[:accounts]
          .where(external_id: customer.extid)
          .delete

        if deleted > 0
          OT.info "[destroy-account] Deleted auth account for extid: #{customer.extid}"
        else
          OT.le "[destroy-account] WARNING: No auth account found for extid: #{customer.extid}"
        end
      rescue StandardError => ex
        OT.le "[destroy-account] Error deleting auth account: #{ex.message}"
        OT.ld ex.backtrace.first(5).join("\n")
        # Don't raise - customer is already deleted, this is cleanup
      end
    end
  end
end
