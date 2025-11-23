# apps/api/colonel/logic/base.rb
#
# frozen_string_literal: true

require_relative '../../base_json_api'

module ColonelAPI
  module Logic
    # Base class for all Colonel API logic classes
    #
    # Inherits from BaseJSONAPI::Logic::Base to get:
    # - Native JSON type responses (not string-serialized)
    # - Standard error handling
    # - Common helper methods
    #
    class Base < BaseJSONAPI::Logic::Base
      # Colonel-specific helpers can go here if needed
    end
  end
end
