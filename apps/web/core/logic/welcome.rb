# apps/web/core/logic/welcome.rb

require_relative '../../../api/v2/logic/base'

module Core
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
          }
        end

        def process
          if @sess['authenticated'] == true
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
            cust = Onetime::Customer.load(checkout_email)

            if cust
              # If the email address is already associated with an account, we can
              # associate the checkout session with that account and then direct
              # them to sign in.

              OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with existing user #{cust.email}"

              cust.apply_fields(**update_customer_fields).commit_fields

              raise OT::Redirect.new('/signin')
            else
              OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with new user #{checkout_email}"

              cust          = Onetime::Customer.create!(checkout_email)
              cust.verified = 'true'
              cust.role     = 'customer'
              cust.update_passphrase Onetime::Utils.strand(12)
              cust.apply_fields(**update_customer_fields).commit_fields

              # Create a completely new session, new id, new everything (incl
              # cookie which the controllor will implicitly do above when it
              # resends the cookie with the new session id).
              OT.info "[FromStripePaymentLink:login-success] #{sess} #{cust.obscure_email} #{cust.role}"

              # Set session authentication data
              sess['external_id'] = cust.extid
              sess['authenticated'] = true
              sess['authenticated_at'] = Familia.now.to_i

            end

          end

          success_data
        end

        def success_data
          { checkout_session_id: checkout_session_id }
        end
      end

      class StripeWebhook < V2::Logic::Base
        attr_reader :event
        attr_accessor :payload, :stripe_signature

        def process_params
          @endpoint_secret = OT.conf.dig('billing', 'webhook_signing_secret')
          @event           = nil
        end

        def raise_concerns
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

          success_data
        end

        def success_data
          response_status  = 200
          response_headers = { 'content-type' => 'application/json' }
          response_content = { welcome: 'thank you' }

          [response_status, response_headers, [response_content.to_json]]
        end
      end
    end
  end
end
