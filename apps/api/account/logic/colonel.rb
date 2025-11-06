# apps/api/account/logic/colonel.rb

# Colonel/Admin Logic Classes
#
# Inherits from V2 logic but uses JSON-type serialization via Account::Logic::Base.
# No business logic changes needed - only serialization format differs.

require_relative '../../v2/logic/colonel'

module AccountAPI
  module Logic
    module Colonel
      # Get colonel info
      class GetColonelInfo < V2::Logic::Colonel::GetColonelInfo
        include AccountAPI::Logic::Base
      end

      # Get colonel stats
      class GetColonelStats < V2::Logic::Colonel::GetColonelStats
        include AccountAPI::Logic::Base
      end
    end
  end
end
