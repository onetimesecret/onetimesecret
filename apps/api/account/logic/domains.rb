# apps/api/account/logic/domains.rb

# Domain Management Logic Classes
#
# Inherits from V2 logic but uses JSON-type serialization via Account::Logic::Base.
# No business logic changes needed - only serialization format differs.

require_relative '../../v2/logic/domains'

module AccountAPI
  module Logic
    module Domains
      # Add domain
      class AddDomain < V2::Logic::Domains::AddDomain
        include AccountAPI::Logic::Base
      end

      # Remove domain
      class RemoveDomain < V2::Logic::Domains::RemoveDomain
        include AccountAPI::Logic::Base
      end

      # Get domain
      class GetDomain < V2::Logic::Domains::GetDomain
        include AccountAPI::Logic::Base
      end

      # Verify domain
      class VerifyDomain < V2::Logic::Domains::VerifyDomain
        include AccountAPI::Logic::Base
      end

      # Update domain brand
      class UpdateDomainBrand < V2::Logic::Domains::UpdateDomainBrand
        include AccountAPI::Logic::Base
      end

      # Get domain brand
      class GetDomainBrand < V2::Logic::Domains::GetDomainBrand
        include AccountAPI::Logic::Base
      end

      # Remove domain image
      class RemoveDomainImage < V2::Logic::Domains::RemoveDomainImage
        include AccountAPI::Logic::Base
      end

      # Update domain image
      class UpdateDomainImage < V2::Logic::Domains::UpdateDomainImage
        include AccountAPI::Logic::Base
      end

      # Get domain image
      class GetDomainImage < V2::Logic::Domains::GetDomainImage
        include AccountAPI::Logic::Base
      end

      # List domains
      class ListDomains < V2::Logic::Domains::ListDomains
        include AccountAPI::Logic::Base
      end
    end
  end
end
