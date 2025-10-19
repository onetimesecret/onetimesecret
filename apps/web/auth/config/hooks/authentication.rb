# apps/web/auth/config/hooks/authentication.rb

module Auth::Config::Hooks::Authentication
  # Pure business logic handlers - no error handling
  module Handlers
    # Updates customer metadata after password change
    #
    # @param account [Hash] Rodauth account hash with :external_id
    def self.update_password_metadata(account)
      return unless account[:external_id]

      customer = Onetime::Customer.find_by_extid(account[:external_id])
      if customer
        customer.passphrase_updated = Familia.now.to_i
        customer.save
        OT.info "[authentication] Updated password metadata for customer: #{customer.custid}"
      else
        OT.info "[authentication] Customer not found for extid: #{account[:external_id]}"
      end
    end
  end

  def self.configure
    proc do
      # Password reset request hook
      after_reset_password_request do
        OT.info "[auth] Password reset requested for: #{account[:email]}"
      end

      # Password reset completion hook
      after_reset_password do
        OT.info "[auth] Password reset for: #{account[:email]}"
      end

      # Password change hook - track metadata in Otto
      after_change_password do
        OT.info "[auth] Password changed for: #{account[:email]}"

        # Update Otto customer password hash if needed
        # Note: Rodauth manages passwords, so Otto just tracks metadata
        Onetime::ErrorHandler.safe_execute('update_password_metadata', email: account[:email]) do
          Handlers.update_password_metadata(account)
        end
      end
    end
  end
end
