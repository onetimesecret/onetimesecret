# apps/api/incoming/logic/incoming.rb
#
# frozen_string_literal: true

# Incoming API Logic Classes
#
# Provides endpoints for the incoming secrets feature, which allows
# anonymous users to send encrypted secrets to pre-configured recipients.
#
# This is the dedicated logic module for the Incoming API application,
# independent of the versioned V2/V3 APIs. Domain-aware: supports both
# canonical domain (global YAML config) and custom domains (per-domain Redis).

require_relative 'base'
require_relative 'get_config'
require_relative 'validate_recipient'
require_relative 'create_incoming_secret'

module Incoming
  module Logic
    # Incoming secrets logic classes:
    # - GetConfig: Returns feature configuration and recipient list
    # - ValidateRecipient: Validates a recipient hash exists
    # - CreateIncomingSecret: Creates secret and notifies recipient
  end
end
