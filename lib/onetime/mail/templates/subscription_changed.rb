# lib/onetime/mail/templates/subscription_changed.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative 'billing_template_helpers'

module Onetime
  module Mail
    module Templates
      # Subscription changed email template.
      #
      # Sent when a customer's subscription plan changes.
      #
      # Required data:
      #   email_address:  Customer's email
      #   old_plan:       Previous plan name
      #   new_plan:       New plan name
      #   effective_date: When the change takes effect
      #
      # Optional data:
      #   is_upgrade: Boolean indicating upgrade vs downgrade
      #
      class SubscriptionChanged < Base
        include BillingTemplateHelpers

        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Old plan required' unless data[:old_plan]
          raise ArgumentError, 'New plan required' unless data[:new_plan]
          raise ArgumentError, 'Effective date required' unless data[:effective_date]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.subscription_changed.subject',
            locale: locale,
            product_name: product_name,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def old_plan
          data[:old_plan]
        end

        def new_plan
          data[:new_plan]
        end

        def effective_date_formatted
          format_timestamp(data[:effective_date])
        end

        def upgrade?
          data[:is_upgrade] == true
        end

        def downgrade?
          data[:is_upgrade] == false
        end

        def change_type
          case data[:is_upgrade]
          when true then 'upgrade'
          when false then 'downgrade'
          else 'change'
          end
        end

        private

        def template_binding
          computed_data = data.merge(
            product_name: product_name,
            display_domain: display_domain,
            old_plan: old_plan,
            new_plan: new_plan,
            effective_date_formatted: effective_date_formatted,
            change_type: change_type,
            upgrade: upgrade?,
            downgrade: downgrade?,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
