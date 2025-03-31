
module V2::Logic
  module Account
    class UpdateLocale < UpdateAccountField
      attr_reader :new_locale, :old_locale

      def process_params
        OT.ld "[UpdateLocale#process_params] params: #{params.inspect}" # careful w/ logging params
        @new_locale = params[field_name] # i.e. :locale
        @old_locale = cust.locale
      end

      def raise_concerns
        # TODO: if new_locale == old_locale, no update needed
        if (!sess.authenticated?) || (cust.anonymous?)
          OT.le "[UpdateLocale#raise-concerns] sess.authenticated?=#{sess.authenticated?} cust.anonymous?=#{cust.anonymous?}"
          raise_form_error "Sorry, we don't support that"
        end
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
        raise_form_error "Invalid locale" unless valid_locale?(new_locale)
      end

      def valid_update?
        valid_locale?(new_locale)
      end

      def perform_update
        cust.locale!(new_locale) # update the single field
      end

      def valid_locale?(locale)
        OT.supported_locales.include?(locale)
      end

      def log_update
        OT.info "[update-account] Locale updated cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress} old/#{old_locale} new/#{new_locale}"
      end
    end
  end
end
