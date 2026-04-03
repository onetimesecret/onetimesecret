# apps/api/v3/logic/incoming.rb
#
# frozen_string_literal: true

# DEPRECATED: V3 Incoming Logic Classes
#
# These classes have been moved to apps/api/incoming/logic/ as part of
# the Incoming API refactor. The Incoming API now uses Incoming::Logic::*
# classes directly instead of delegating to V3::Logic::Incoming::*.
#
# This file is retained temporarily for backward compatibility.
# Remove after confirming no other code depends on V3::Logic::Incoming.
#
# See: apps/api/incoming/logic/incoming.rb for the new location.
#
# Original description:
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
