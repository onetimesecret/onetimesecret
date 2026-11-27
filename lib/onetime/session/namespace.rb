# lib/onetime/session/namespace.rb
#
# frozen_string_literal: true

require 'rack/session/abstract/id'

module Onetime
  # Declare the Rack store class for helpers that load without its implementation.
  class Session < Rack::Session::Abstract::PersistedSecure; end
end
