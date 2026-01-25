# apps/web/core/logic/base.rb
#
# frozen_string_literal: true

require_relative '../../../../lib/onetime/logic/base'

module Core
  module Logic
    # Base class for Core Web application logic classes.
    #
    # Inherits from Onetime::Logic::Base for common functionality.
    # Can be extended with Core-specific helpers as needed.
    class Base < Onetime::Logic::Base
      # Core-specific logic can be added here if needed
    end
  end
end
