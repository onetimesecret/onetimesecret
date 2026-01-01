# frozen_string_literal: true

require_relative 'base'
require_relative 'billing_template_helpers'

module Onetime
  module Mail
    module Templates
      # Payment failed email template.
      #
      # Sent when a payment attempt fails.
      #
      # Required data:
      #   email_address:  Customer's email
      #   amount:         Failed payment amount
      #   currency:       Currency code
      #   plan_name:      Subscription plan name
      #   failure_reason: Human-readable reason
      #
      # Optional data:
      #   retry_date:        When next retry occurs
      #   update_payment_url: Link to update payment method
      #
      class PaymentFailed < Base
        include BillingTemplateHelpers

        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Amount required' unless data[:amount]
          raise ArgumentError, 'Currency required' unless data[:currency]
          raise ArgumentError, 'Plan name required' unless data[:plan_name]
          raise ArgumentError, 'Failure reason required' unless data[:failure_reason]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.payment_failed.subject',
            locale: locale,
            product_name: product_name,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def failure_reason
          data[:failure_reason]
        end

        def retry_date_formatted
          return nil unless data[:retry_date]

          format_timestamp(data[:retry_date])
        end

        def update_payment_url
          data[:update_payment_url]
        end

        private

        def template_binding
          computed_data = data.merge(
            product_name: product_name,
            display_domain: display_domain,
            formatted_amount: formatted_amount,
            failure_reason: failure_reason,
            retry_date_formatted: retry_date_formatted,
            update_payment_url: update_payment_url,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
