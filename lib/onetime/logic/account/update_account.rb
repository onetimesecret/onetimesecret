

module Onetime::Logic
  module Account

    class UpdateAccount < OT::Logic::Base
      attr_reader :modified, :greenlighted

      def process_params
        @currentp = self.class.normalize_password(params[:currentp])
        @newp = self.class.normalize_password(params[:newp])
        @newp2 = self.class.normalize_password(params[:newp2])
      end

      def raise_concerns
        @modified ||= []
        limit_action :update_account
        if ! @currentp.empty?
          raise_form_error "Current password is incorrect" unless cust.passphrase?(@currentp)
          raise_form_error "New password cannot be the same as current password" if @newp == @currentp
          raise_form_error "New password is too short" unless @newp.size >= 6
          raise_form_error "New passwords do not match" unless @newp == @newp2
        end
      end

      def process
        if cust.passphrase?(@currentp) && @newp == @newp2
          @greenlighted = true
          OT.info "[update-account] Password updated cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress}"

          cust.update_passphrase! @newp
          @modified << :password
        end
      end

      def modified? field_name
        modified.member? field_name
      end

      def success_data
        {}
      end
    end
  end
end
