# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Payment receipt email template.
      #
      # Sent after successful payment processing.
      #
      # Required data:
      #   email_address: Customer's email
      #   amount:        Payment amount (numeric)
      #   currency:      Currency code (e.g., 'usd')
      #   plan_name:     Subscription plan name
      #   invoice_id:    Stripe invoice ID
      #   paid_at:       Timestamp when paid
      #
      # Optional data:
      #   invoice_url:   Stripe hosted invoice link
      #
      class PaymentReceipt < Base
        CURRENCY_SYMBOLS = {
          'usd' => '$',
          'eur' => '€',
          'gbp' => '£',
          'cad' => 'CA$',
          'aud' => 'A$',
          'jpy' => '¥',
        }.freeze

        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Amount required' unless data[:amount]
          raise ArgumentError, 'Currency required' unless data[:currency]
          raise ArgumentError, 'Plan name required' unless data[:plan_name]
          raise ArgumentError, 'Invoice ID required' unless data[:invoice_id]
          raise ArgumentError, 'Paid at required' unless data[:paid_at]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.payment_receipt.subject',
            locale: locale,
            product_name: product_name,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def formatted_amount
          amount = data[:amount]
          currency = data[:currency].to_s.downcase

          display_amount = amount.is_a?(Integer) && amount > 100 ? amount / 100.0 : amount.to_f
          symbol = CURRENCY_SYMBOLS.fetch(currency, "#{currency.upcase} ")

          "#{symbol}#{'%.2f' % display_amount}"
        end

        def paid_at_formatted
          format_timestamp(data[:paid_at])
        end

        def invoice_url
          data[:invoice_url]
        end

        private

        def format_timestamp(timestamp)
          time = case timestamp
                 when Time then timestamp
                 when Integer then Time.at(timestamp)
                 when String then Time.parse(timestamp)
                 else timestamp
                 end
          time.strftime('%B %d, %Y')
        rescue StandardError
          timestamp.to_s
        end

        def template_binding
          computed_data = data.merge(
            product_name: product_name,
            display_domain: display_domain,
            formatted_amount: formatted_amount,
            paid_at_formatted: paid_at_formatted,
            invoice_url: invoice_url,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
