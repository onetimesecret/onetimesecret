# lib/onetime/mail/templates/billing_template_helpers.rb
#
# frozen_string_literal: true

module Onetime
  module Mail
    module Templates
      # Shared helpers for billing-related email templates
      module BillingTemplateHelpers
        CURRENCY_SYMBOLS = {
          'usd' => '$',
          'eur' => '€',
          'gbp' => '£',
          'cad' => 'CA$',
          'aud' => 'A$',
          'jpy' => '¥',
        }.freeze

        def formatted_amount
          amount   = data[:amount]
          currency = data[:currency].to_s.downcase

          display_amount = amount.is_a?(Integer) && amount > 100 ? amount / 100.0 : amount.to_f
          symbol         = CURRENCY_SYMBOLS.fetch(currency, "#{currency.upcase} ")

          "#{symbol}#{format('%.2f', display_amount)}"
        end

        def format_timestamp(timestamp)
          time = case timestamp
                 when Integer then Time.at(timestamp)
                 when String then Time.parse(timestamp)
                 else timestamp
                 end
          time.strftime('%B %d, %Y')
        rescue StandardError
          timestamp.to_s
        end
      end
    end
  end
end
