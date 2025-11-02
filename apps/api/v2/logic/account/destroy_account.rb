module V2::Logic
  module Account
    class DestroyAccount < V2::Logic::Base
      attr_reader :raised_concerns_was_called, :greenlighted

      def process_params
        return if params.nil?

        OT.ld "[DestroyAccount#process_params] params: #{params.inspect}"
        @confirmation = self.class.normalize_password(params[:confirmation])
      end

      def raise_concerns
        @raised_concerns_was_called = true

        if @confirmation&.empty?
          raise_form_error 'Password confirmation is required.', field: 'confirmation', error_type: 'required'
        else
          OT.info "[destroy-account] Passphrase check attempt cid/#{cust.objid} r/#{cust.role} ipa/#{session_sid}"

          raise_form_error 'Please check the password.', field: 'confirmation', error_type: 'incorrect' unless cust.passphrase?(@confirmation)
        end
      end

      def process
        # This is very defensive programming. When it comes to
        # destroying things though, let's pull out all the stops.
        raise_form_error 'We have concerns about that request.' unless raised_concerns_was_called

        return unless cust.passphrase?(@confirmation)

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

          # If in advanced mode, also delete from auth database
          delete_auth_account(cust) if Onetime.auth_config.advanced_enabled?
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
        { custid: @cust.custid }
      end

      private

      # Delete account from auth database in advanced mode
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
      rescue StandardError => e
        OT.le "[destroy-account] Error deleting auth account: #{e.message}"
        OT.ld e.backtrace.first(5).join("\n")
        # Don't raise - customer is already deleted, this is cleanup
      end
    end
  end
end
