require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class GetDomainBrand < OT::Logic::Base
      attr_reader :greenlighted, :display_domain, :custom_domain
    end
  end
end
