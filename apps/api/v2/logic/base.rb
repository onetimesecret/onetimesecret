# apps/api/v2/logic/base.rb
#
# frozen_string_literal: true

require_relative '../../../../lib/onetime/logic/base'
require_relative 'helpers'

module V2
  module Logic
    # V2 API Logic Base Class
    #
    # Extends Onetime::Logic::Base with V2-specific helpers.
    # Provides i18n and URI helper methods for V2 API logic classes.
    #
    # For backward compatibility, this class maintains the V2::Logic::Base
    # interface while delegating core functionality to Onetime::Logic::Base.
    class Base < Onetime::Logic::Base
      include V2::Logic::UriHelpers
    end
  end
end
