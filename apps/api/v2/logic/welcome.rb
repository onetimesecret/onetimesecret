# apps/api/v2/logic/welcome.rb

require_relative 'base'

module V2
  module Logic
    module Welcome
      class FromStripePaymentLink < V2::Logic::Base
        attr_reader :checkout_session_id, :checkout_session, :checkout_email, :update_customer_fields

        def process_params
          @checkout_session_id = params[:checkout]
        end

        def raise_concerns
          raise_form_error 'No Stripe checkout_session_id' unless checkout_session_id
          @checkout_session = Stripe::Checkout::Session.retrieve(checkout_session_id)
          raise_form_error 'Invalid Stripe checkout session' unless checkout_session

          @checkout_email         = checkout_session.customer_details.email
          @update_customer_fields = {
            stripe_checkout_email: checkout_email,
            stripe_subscription_id: checkout_session.subscription,
            stripe_customer_id: checkout_session.customer,
            planid: 'identity',
          }
        end

        def process
          if sess.authenticated?
            # If the user is already authenticated, we can associate the checkout
            # session with their account.

            if checkout_email.eql?(cust.email)
              OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with authenticated user #{cust.email}"

            else
              # Log the discrepancy
              OT.le "[FromStripePaymentLink] Email mismatch: #{checkout_email} !== authenticated user email #{cust.email}"
            end

            # Proceed with associating the checkout session with the
            # authenticated account.

            # TODO: Handle case where the user is already a Stripe customer
            cust.apply_fields(**update_customer_fields).commit_fields

          else
            # If the user is not authenticated, check if the email address is already
            # associated with an account. If not, we can create a new account for them
            # using the email address from the checkout session.
            cust = V2::Customer.load(checkout_email)

            if cust
              # If the email address is already associated with an account, we can
              # associate the checkout session with that account and then direct
              # them to sign in.

              OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with existing user #{cust.email}"

              cust.apply_fields(**update_customer_fields).commit_fields

              raise OT::Redirect.new('/signin')
            else
              OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with new user #{checkout_email}"

              cust          = V2::Customer.create(checkout_email)
              cust.planid   = 'identity'
              cust.verified = 'true'
              cust.role     = 'customer'
              cust.update_passphrase Onetime::Utils.strand(12)
              cust.apply_fields(**update_customer_fields).commit_fields

              # Create a completely new session, new id, new everything (incl
              # cookie which the controllor will implicitly do above when it
              # resends the cookie with the new session id).
              sess.replace!

              OT.info "[FromStripePaymentLink:login-success] #{sess.short_identifier} #{cust.obscure_email} #{cust.role} (new sessid)"

              sess.apply_fields custid: cust.custid, authenticated: 'true'
              sess.ttl = session_ttl if @stay # TODO
              sess.save

            end

          end
        end
      end

      class StripeWebhook < V2::Logic::Base
        attr_reader :event
        attr_accessor :payload, :stripe_signature

        def process_params
          @endpoint_secret = OT.conf.dig(:site, :plans, :webook_signing_secret)
          @event           = nil
        end

        def raise_concerns
          #limit_action :stripe_webhook
          raise_form_error 'No endpoint secret set' unless @endpoint_secret
          raise_form_error 'No Stripe payload' unless payload
          raise_form_error 'No Stripe signature' unless stripe_signature

          begin
            @event = Stripe::Webhook.construct_event(
              payload,
              stripe_signature,
              @endpoint_secret,
            )
          rescue JSON::ParserError => ex
            OT.le "[webhook] JSON parsing error: #{ex}: sig:#{stripe_signature}"
            raise_form_error 'Invalid payload'
          rescue Stripe::SignatureVerificationError => ex
            OT.le "[webhook] Signature verification failed: #{ex}: sig:#{stripe_signature}"
            raise_form_error 'Bad signature'
          end
        end

        def process
          OT.ld "[webhook: #{event.type}] Event data: #{event.data}"

          case event.type
          when 'checkout.session.completed'
            session = event.data.object
            # Handle successful checkout
            OT.info "[webhook: #{event.type}] session: #{session} "

          when 'customer.subscription.created'
            subscription = event.data.object
            # Handle new subscription
            # ... handle other events as needed
            OT.info "[webhook: #{event.type}] subscription: #{subscription} "

          else
            OT.info "[webhook: #{event.type}] Unhandled event"
          end

          response_status  = 200
          response_headers = { 'Content-Type' => 'application/json' }
          response_content = { welcome: 'thank you' }

          [response_status, response_headers, [response_content.to_json]]
        end
      end
    end
  end
end
