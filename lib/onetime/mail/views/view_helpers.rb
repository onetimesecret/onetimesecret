# lib/onetime/mail/views/view_helpers.rb

require 'core/views/helpers/sanitizer'

module Onetime
  module Mail

    module ViewHelpers # rubocop:disable Style/Documentation
      include Core::Views::SanitizerHelpers
    end

  end
end
