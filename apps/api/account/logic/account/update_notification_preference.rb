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
    # Future notification types can be added by extending FIELDS.
    #
    # ## Explicit dispatch, never reflection
    #
    # The request's `field` param only ever SELECTS an entry in FIELDS; it is
    # never turned into a method name. The earlier `cust.send(field)` was
    # allowlist-gated and safe, but the allowlist and the reflection were two
    # things that had to agree, and a scanner cannot see the gate (CodeQL
    # rb/code-injection). One table now holds both the allowlist and the
    # accessors, so an unknown or hostile name reaches nothing on the customer.
    #
    class UpdateNotificationPreference < UpdateAccountField
      # How to read and write one preference on a customer.
      Accessor = Data.define(:read, :write)

      # Every updatable preference, keyed by its wire name. Adding a
      # notification type is one entry here.
      FIELDS = {
        'notify_on_reveal' => Accessor.new(
          read: ->(cust) { cust.notify_on_reveal },
          write: ->(cust, value) { cust.notify_on_reveal = value },
        ),
      }.freeze

      # Notification preference fields that can be updated (wire names).
      VALID_FIELDS = FIELDS.keys.freeze

      attr_reader :preference_field, :preference_value, :old_value

      def process_params
        @preference_field = params['field'].to_s
        @preference_value = params['value'].to_s == 'true'
        @old_value        = FIELDS.fetch(preference_field).read.call(cust) if valid_field?
      end

      def raise_concerns
        verify_authenticated!
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
        FIELDS.key?(preference_field)
      end

      def valid_update?
        valid_field?
      end

      def perform_update
        raise_form_error 'Invalid field' unless valid_field?

        FIELDS.fetch(preference_field).write.call(cust, preference_value.to_s)
        cust.save
      end

      def log_update
        OT.info "[update-notification-preference] #{preference_field} updated cid/#{cust.objid} " \
                "old/#{old_value} new/#{preference_value}"
      end
    end
  end
end
