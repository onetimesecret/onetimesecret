# apps/api/v2/logic/exceptions.rb

require 'v1/logic/exceptions'

require_relative 'base'

module V2::Logic
  # Handles incoming exception reports similar to Sentry's basic functionality
  class ReceiveException < V1::Logic::ReceiveException
  end
end
