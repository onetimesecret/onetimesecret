# apps/api/v3/logic/incoming.rb
#
# frozen_string_literal: true

# V3 Incoming Logic Classes
#
# Provides endpoints for the incoming secrets feature, which allows
# anonymous users to send encrypted secrets to pre-configured recipients.

require_relative 'incoming/get_config'
require_relative 'incoming/validate_recipient'
require_relative 'incoming/create_incoming_secret'

module V3
  module Logic
    module Incoming
      # Incoming secrets logic classes
    end
  end
end
