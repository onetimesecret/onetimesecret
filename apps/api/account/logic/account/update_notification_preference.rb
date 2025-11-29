# apps/api/account/logic/account/update_notification_preference.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Account
    # Update notification preference settings for a customer
    #
    # Supports updating notification-related boolean fields like:
    # - notify_on_reveal: Notify when a secret is revealed
    #
    # Future notification types can be added by extending VALID_FIELDS.
    #
    class UpdateNotificationPreference < UpdateAccountField
      # Notification preference fields that can be updated
      VALID_FIELDS = %w[notify_on_reveal].freeze

      attr_reader :preference_field, :preference_value, :old_value

      def process_params
        @preference_field = params['field'].to_s
        @preference_value = params['value'].to_s == 'true'
        @old_value = cust.send(preference_field) if valid_field?
      end

      def raise_concerns
        raise_form_error 'Not authenticated' if cust.anonymous?
        raise_form_error 'Invalid field' unless valid_field?
      end

      def success_data
        {
          record: {
            preference_field => preference_value,
          },
          old_value: old_value,
        }
      end

      private

      def field_name
        preference_field.to_sym
      end

      def field_specific_concerns
        # No additional concerns for notification preferences
      end

      def valid_field?
        VALID_FIELDS.include?(preference_field)
      end

      def valid_update?
        valid_field?
      end

      def perform_update
        cust.send("#{preference_field}=", preference_value.to_s)
        cust.save
      end

      def log_update
        OT.info "[update-notification-preference] #{preference_field} updated cid/#{cust.objid} " \
                "old/#{old_value} new/#{preference_value}"
      end
    end
  end
end
