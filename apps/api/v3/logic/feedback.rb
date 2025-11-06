# apps/api/v3/logic/feedback.rb

# V3 Feedback Logic
#
# Inherits from V2 feedback logic. No changes needed as feedback endpoints
# already return native types (not model serialization).

require_relative '../../v2/logic/feedback'

module V3
  module Logic
    class ReceiveFeedback < V2::Logic::ReceiveFeedback
      # No overrides needed - V2 implementation already returns native types
    end
  end
end
