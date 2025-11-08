# apps/api/account/logic/account/update_password.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Account
    class UpdatePassword < UpdateAccountField
      def process_params
        OT.ld "[UpdatePassword#process_params] params: #{params.inspect}"
        @password        = self.class.normalize_password(params[:password]) # was currentp
        @newpassword     = self.class.normalize_password(params[:newpassword]) # was newp
        @passwordconfirm = self.class.normalize_password(params['password-confirm']) # was newp2
      end

      def success_data
        {}
      end

      private

      def field_name
        :password
      end

      def field_specific_concerns
        return if @password.empty?

        raise_form_error 'Current password is incorrect', field: 'password', error_type: 'incorrect' unless cust.passphrase?(@password)
        raise_form_error 'New password cannot be the same as current password', field: 'newpassword', error_type: 'same_as_current' if @newpassword == @password
        raise_form_error 'New password is too short', field: 'newpassword', error_type: 'too_short' unless @newpassword.size >= 6
        raise_form_error 'New passwords do not match', field: 'passwordconfirm', error_type: 'mismatch' unless @newpassword == @passwordconfirm
      end

      def valid_update?
        cust.passphrase?(@password) && @newpassword == @passwordconfirm
      end

      def perform_update
        cust.update_passphrase! @newpassword
      end
    end
  end
end
