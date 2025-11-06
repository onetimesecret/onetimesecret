# apps/api/account/logic/account.rb

# Account Management Logic Classes
#
# Inherits from V2 logic but uses JSON-type serialization via Account::Logic::Base.
# No business logic changes needed - only serialization format differs.

require_relative '../../v2/logic/account'

module AccountAPI
  module Logic
    module Accounts
      # Destroy account
      class DestroyAccount < V2::Logic::Account::DestroyAccount
        include AccountAPI::Logic::Base
      end

      # Update password
      class UpdatePassword < V2::Logic::Account::UpdatePassword
        include AccountAPI::Logic::Base
      end

      # Update locale
      class UpdateLocale < V2::Logic::Account::UpdateLocale
        include AccountAPI::Logic::Base
      end

      # Generate API token
      class GenerateAPIToken < V2::Logic::Account::GenerateAPIToken
        include AccountAPI::Logic::Base
      end

      # Get account details
      class GetAccount < V2::Logic::Account::GetAccount
        include AccountAPI::Logic::Base
      end
    end
  end
end
