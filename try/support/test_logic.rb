# try/support/test_logic.rb
#
# frozen_string_literal: true

require_relative 'test_models'

require 'onetime/logic'

# Load AccountAPI logic classes
require 'apps/api/account/logic/base'
require 'apps/api/account/logic/account'
require 'apps/api/account/logic/authentication'

Logic = V2::Logic
