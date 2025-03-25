

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

        # It's vitally important for the limiter to run prior to any
        # other concerns. This prevents a malicious user from
        # attempting to brute force the password.
        #
        limit_action :destroy_account

        if @confirmation&.empty?
          raise_form_error "Password confirmation is required."
        else
          OT.info "[destroy-account] Passphrase check attempt cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress}"

          unless cust.passphrase?(@confirmation)
            raise_form_error "Please check the password."
          end
        end
      end

      def process
        # This is very defensive programming. When it comes to
        # destroying things though, let's pull out all the stops.
        unless raised_concerns_was_called
          raise_form_error "We have concerns about that request."
        end

        if cust.passphrase?(@confirmation)
          # All criteria to destroy the account have been met.
          @greenlighted = true

          # Process the customer's request to destroy their account.
          # TODO: Limit to dev as well
          if Onetime.debug
            OT.ld "[destroy-account] Simulated account destruction #{cust.custid} #{cust.role} #{sess.ipaddress}"

            # Since we intentionally don't call Customer#destroy_requested!
            # when running in debug mode (to simulate the destruction but
            # not actually modify the customer record), the tryouts that
            # checked the state of the customer record after destroying
            # will fail (e.g. they expect the passphrase to be removed).

            # We add a message to the session to let the debug user know
            # that we made it to this point in the logic. Otherwise, they
            # might not know if the action was successful or not since we
            # don't actually destroy the account in debug mode.
            sess.set_info_message 'Account deleted'

          else
            cust.destroy_requested!

            # Log the event immediately after saving the change to
            # to minimize the chance of the event not being logged.
            OT.info "[destroy-account] Account destroyed. #{cust.custid} #{cust.role} #{sess.ipaddress}"
          end

          # We replace the session and session ID and then add a message
          # for the user so that when the page they're directed to loads
          # (i.e. the homepage), they'll see it and remember what they did.
          sess.replace!
          sess.set_info_message 'Account deleted'
        end

      end

      def modified? guess
        modified.member? guess
      end

      def success_data
        { custid: @cust.custid }
      end

    end

  end
end
