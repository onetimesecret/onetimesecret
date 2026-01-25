# lib/onetime/mail/views/trial_expiring.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative 'billing_template_helpers'

module Onetime
  module Mail
    module Templates
      # Trial expiring email template.
      #
      # Sent when a customer's trial period is about to end.
      #
      # Required data:
      #   email_address:  Customer's email
      #   plan_name:      Trial plan name
      #   trial_ends_at:  Timestamp when trial expires
      #   days_remaining: Days until trial ends
      #
      # Optional data:
      #   upgrade_url: Link to upgrade/billing page
      #
      class TrialExpiring < Base
        include BillingTemplateHelpers

        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Plan name required' unless data[:plan_name]
          raise ArgumentError, 'Trial ends at required' unless data[:trial_ends_at]
          raise ArgumentError, 'Days remaining required' unless data[:days_remaining]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.trial_expiring.subject',
            locale: locale,
            product_name: product_name,
            days_remaining: days_remaining,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def plan_name
          data[:plan_name]
        end

        def days_remaining
          data[:days_remaining].to_i
        end

        def trial_ends_at_formatted
          format_timestamp(data[:trial_ends_at])
        end

        def upgrade_url
          data[:upgrade_url]
        end

        def urgent?
          days_remaining <= 3
        end

        def last_day?
          days_remaining <= 1
        end

        private

        def template_binding
          computed_data = data.merge(
            product_name: product_name,
            display_domain: display_domain,
            plan_name: plan_name,
            days_remaining: days_remaining,
            trial_ends_at_formatted: trial_ends_at_formatted,
            upgrade_url: upgrade_url,
            urgent: urgent?,
            last_day: last_day?,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
