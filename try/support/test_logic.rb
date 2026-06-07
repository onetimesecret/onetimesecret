# try/support/test_logic.rb
#
# frozen_string_literal: true

require_relative 'test_models'

# Load GuestRouteGating before V2 logic classes that include it
require 'onetime/logic/guest_route_gating'
require 'onetime/logic'

# Load AccountAPI logic classes
require 'api/account/logic/base'
require 'api/account/logic/account'
require 'api/account/logic/authentication'

Logic = V2::Logic
