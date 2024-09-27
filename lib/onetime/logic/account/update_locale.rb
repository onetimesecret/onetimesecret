
module Onetime::Logic
  module Account
    class UpdateLocale < UpdateAccountField
      attr_reader :new_locale, :old_locale

      def process_params
        OT.ld "[UpdateLocale#process_params] params: #{params.inspect}"
        @new_locale = params[:locale]
        @old_locale = cust.locale
      end

      def success_data
        {
          new_locale: new_locale,
          old_locale: old_locale
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
        valid_locale?(new_locale) && new_locale != old_locale
      end

      def perform_update
        cust.update_locale!(new_locale) # update the single field
      end

      def valid_locale?(locale)
        supported_locales = OT.conf.fetch(:locales, []).map(&:to_s)
        supported_locales.include?(locale)
      end

      def log_update
        OT.info "[update-account] Locale updated cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress} old/#{old_locale} new/#{new_locale}"
      end
    end
  end
end
