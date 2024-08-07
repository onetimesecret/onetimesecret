
require_relative 'base'

module Onetime::Logic
  module Welcome

    class ExampleClass < OT::Logic::Base
      def process_params
      end

      def raise_concerns
        limit_action :example_class
      end

      def process
      end
    end

    class FromStripePaymentLink < OT::Logic::Base
      attr_reader :checkout_session_id, :checkout_session, :checkout_email, :update_customer_fields

      def process_params
        @checkout_session_id = params[:checkout]
      end

      def raise_concerns
        raise_form_error "No Stripe checkout_session_id" unless checkout_session_id
        @checkout_session = Stripe::Checkout::Session.retrieve(checkout_session_id)
        raise_form_error "Invalid Stripe checkout session" unless checkout_session

        @checkout_email = checkout_session.customer_details.email
        @update_customer_fields = {
          stripe_checkout_email: checkout_email,
          stripe_subscription_id: checkout_session.subscription,
          stripe_customer_id: checkout_session.customer,
          planid: 'identity'
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
          cust.update_fields(**update_customer_fields)

        else
          # If the user is not authenticated, check if the email address is already
          # associated with an account. If not, we can create a new account for them
          # using the email address from the checkout session.
          cust = OT::Customer.load(checkout_email)

          if cust
            # If the email address is already associated with an account, we can
            # associate the checkout session with that account and then direct
            # them to sign in.

            OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with existing user #{cust.email}"

            cust.update_fields(**update_customer_fields)

            raise OT::Redirect.new('/signin')
          else
            OT.info "[FromStripePaymentLink] Associating checkout #{checkout_session_id} with new user #{checkout_email}"

            cust = OT::Customer.create(checkout_email)
            cust.planid = "identity"
            cust.verified = "true"
            cust.role = "customer"
            cust.update_passphrase Onetime::Utils.strand(12)
            cust.update_fields(**update_customer_fields)

            # Create a completely new session, new id, new everything (incl
            # cookie which the controllor will implicitly do above when it
            # resends the cookie with the new session id).
            sess.replace!

            OT.info "[FromStripePaymentLink:login-success] #{sess.short_identifier} #{cust.obscure_email} #{cust.role} (new sessid)"

            sess.update_fields :custid => cust.custid, :authenticated => 'true'
            sess.ttl = session_ttl if @stay
            sess.save

          end



        end

      end
    end

    class StripeWebhook < OT::Logic::Base
      attr_reader :event
      attr_accessor :payload, :stripe_signature

      def process_params
        @endpoint_secret = OT.conf.dig(:site, :plans, :webook_signing_secret)
        @event = nil
      end

      def raise_concerns
        #limit_action :stripe_webhook
        raise_form_error "No endpoint secret set" unless @endpoint_secret
        raise_form_error "No Stripe payload" unless payload
        raise_form_error "No Stripe signature" unless stripe_signature

        begin
          @event = Stripe::Webhook.construct_event(
            payload,
            stripe_signature,
            @endpoint_secret
          )

        rescue JSON::ParserError => e
          OT.le "[webhook] JSON parsing error: #{e}: sig:#{stripe_signature}"
          raise_form_error "Invalid payload"

        rescue Stripe::SignatureVerificationError => e
          OT.le "[webhook] Signature verification failed: #{e}: sig:#{stripe_signature}"
          raise_form_error "Bad signature"
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

        response_status = 200
        response_headers = { 'Content-Type' => 'application/json' }
        response_content = { welcome: 'thank you' }

        [response_status, response_headers, [response_content.to_json]]
      end
    end

  end
end

__END__
{
  "id": "cs_test_a1rXKe8udp",
  "object": "checkout.session",
  "after_expiration": null,
  "allow_promotion_codes": false,
  "amount_subtotal": 2500,
  "amount_total": 2500,
  "automatic_tax": {
    "enabled": true,
    "liability": {
      "type": "self"
    },
    "status": "complete"
  },
  "billing_address_collection": "auto",
  "cancel_url": "https://stripe.com",
  "client_reference_id": "",
  "client_secret": null,
  "consent": null,
  "consent_collection": {
    "payment_method_reuse_agreement": null,
    "promotions": "none",
    "terms_of_service": "none"
  },
  "created": 1722978823,
  "currency": "usd",
  "currency_conversion": null,
  "custom_fields": [],
  "custom_text": {
    "after_submit": null,
    "shipping_address": null,
    "submit": null,
    "terms_of_service_acceptance": null
  },
  "customer": "cus_Qc8zvS3zCmHusS",
  "customer_creation": "if_required",
  "customer_details": {
    "address": {
      "city": null,
      "country": "CA",
      "line1": null,
      "line2": null,
      "postal_code": "H2W 1Y7",
      "state": null
    },
    "email": "gregproops@example.com",
    "name": "Greg Proops",
    "phone": null,
    "tax_exempt": "none",
    "tax_ids": []
  },
  "customer_email": null,
  "expires_at": 1723065223,
  "invoice": "in_1PkuhzHA8OZxV3C",
  "invoice_creation": null,
  "livemode": false,
  "locale": "auto",
  "metadata": {},
  "mode": "subscription",
  "payment_intent": null,
  "payment_link": "plink_1PMwedHA8OZxV3Cy",
  "payment_method_collection": "always",
  "payment_method_configuration_details": null,
  "payment_method_options": {
    "card": {
      "request_three_d_secure": "automatic"
    }
  },
  "payment_method_types": [
    "card"
  ],
  "payment_status": "paid",
  "phone_number_collection": {
    "enabled": false
  },
  "recovered_from": null,
  "saved_payment_method_options": {
    "allow_redisplay_filters": [
      "always"
    ],
    "payment_method_remove": null,
    "payment_method_save": null
  },
  "setup_intent": null,
  "shipping_address_collection": null,
  "shipping_cost": null,
  "shipping_details": null,
  "shipping_options": [],
  "status": "complete",
  "submit_type": "auto",
  "subscription": "sub_1PkuhzHA8OZxV3CzA",
  "success_url": "https://staging.onetimesecret.com/welcome?checkout={CHECKOUT_SESSION_ID}",
  "tax_id_collection": {
    "enabled": true
  },
  "total_details": {
    "amount_discount": 0,
    "amount_shipping": 0,
    "amount_tax": 0
  },
  "ui_mode": "hosted",
  "url": null
}
