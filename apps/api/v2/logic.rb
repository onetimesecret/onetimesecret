# apps/api/v2/logic.rb
#
# frozen_string_literal: true

require_relative 'logic/base'
require_relative 'logic/meta'

# GuestRouteGating must be loaded before secrets classes that include it
require 'onetime/logic/guest_route_gating'
require_relative 'logic/secrets'
