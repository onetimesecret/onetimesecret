
module Onetime::Logic
  module Account

    # The UpdatePassword class handles the logic for updating a user's account information,
    # specifically focusing on password updates. It inherits from OT::Logic::Base.
    class UpdatePassword < OT::Logic::Base
      # @!attribute [r] modified
      #   @return [Array<Symbol>] A list of fields that have been modified.
      attr_reader :modified

      # @!attribute [r] greenlighted
      #   @return [Boolean] Indicates whether the account update has been approved.
      attr_reader :greenlighted

      # Processes the parameters related to password updates.
      # Normalizes the current password, new password, and confirmation of the new password.
      def process_params
        @currentp = self.class.normalize_password(params[:currentp])
        @newp = self.class.normalize_password(params[:newp])
        @newp2 = self.class.normalize_password(params[:newp2])
      end

      # Raises concerns if any of the password update conditions are not met.
      # Checks include:
      # - Current password correctness
      # - New password not being the same as the current password
      # - New password length being at least 6 characters
      # - New password matching the confirmation password
      def raise_concerns
        @modified ||= []
        limit_action :update_account
        if !@currentp.empty?
          raise_form_error "Current password is incorrect" unless cust.passphrase?(@currentp)
          raise_form_error "New password cannot be the same as current password" if @newp == @currentp
          raise_form_error "New password is too short" unless @newp.size >= 6
          raise_form_error "New passwords do not match" unless @newp == @newp2
        end
      end

      # Processes the password update if all conditions are met.
      # Updates the password and logs the update.
      def process
        if cust.passphrase?(@currentp) && @newp == @newp2
          @greenlighted = true
          OT.info "[update-account] Password updated cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress}"

          cust.update_passphrase! @newp
          @modified << :password
        end
      end

      # Checks if a specific field has been modified.
      # @param field_name [Symbol] The name of the field to check.
      # @return [Boolean] True if the field has been modified, false otherwise.
      def modified?(field_name)
        modified.member?(field_name)
      end

      # Returns data indicating the success of the operation.
      # @return [Hash] An empty hash in this case.
      def success_data
        {}
      end
    end
  end
end
