# apps/api/account/logic/account/update_locale.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Account
    class UpdateLocale < UpdateAccountField
      attr_reader :new_locale, :old_locale

      def process_params
        OT.ld "[UpdateLocale#process_params] params: #{params.inspect}" # careful w/ logging params
        @new_locale = params[field_name] # i.e. :locale
        @old_locale = cust.locale
      end

      def raise_concerns
        # Allow both authenticated and anonymous users to update locale
        # Anonymous users update session only; authenticated users update their account
      end

      def success_data
        {
          new_locale: new_locale,
          old_locale: old_locale,
        }
      end

      private

      def field_name
        :locale
      end

      def field_specific_concerns
        raise_form_error 'Invalid locale' unless valid_locale?(new_locale)
      end

      def valid_update?
        valid_locale?(new_locale)
      end

      def perform_update
        # Always update session locale (works for both anonymous and authenticated)
        OT.ld "[UpdateLocale#perform_update] Setting session['locale'] = #{new_locale}"
        OT.ld "[UpdateLocale#perform_update] Session before: #{sess.inspect}"
        sess['locale'] = new_locale
        OT.ld "[UpdateLocale#perform_update] Session after: #{sess.inspect}"

        # Only update customer record if authenticated
        unless cust.anonymous?
          cust.locale!(new_locale)
        end
      end

      def valid_locale?(locale)
        OT.supported_locales.include?(locale)
      end

      def log_update
        if cust.anonymous?
          OT.info "[update-locale] Anonymous session locale updated sid/#{session_sid} old/#{old_locale} new/#{new_locale}"
        else
          OT.info "[update-locale] Customer locale updated cid/#{cust.objid} r/#{cust.role} sid/#{session_sid} old/#{old_locale} new/#{new_locale}"
        end
      end
    end
  end
end
