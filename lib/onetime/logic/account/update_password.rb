module Onetime::Logic
  module Account
    class UpdatePassword < UpdateAccountField
      def process_params
        OT.ld "[UpdatePassword#process_params] params: #{params.inspect}"
        @currentp = self.class.normalize_password(params[:currentp])
        @newp = self.class.normalize_password(params[:newp])
        @newp2 = self.class.normalize_password(params[:newp2])
      end

      def success_data
        {}
      end

      private

      def field_name
        :password
      end

      def field_specific_concerns
        if !@currentp.empty?
          raise_form_error "Current password is incorrect" unless cust.passphrase?(@currentp)
          raise_form_error "New password cannot be the same as current password" if @newp == @currentp
          raise_form_error "New password is too short" unless @newp.size >= 6
          raise_form_error "New passwords do not match" unless @newp == @newp2
        end
      end

      def valid_update?
        cust.passphrase?(@currentp) && @newp == @newp2
      end

      def perform_update
        cust.update_passphrase! @newp
      end
    end
  end
end
