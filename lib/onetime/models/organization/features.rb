# lib/onetime/models/organization/features.rb
#
# frozen_string_literal: true

# Organization features loader
# Uses Familia::Features::Autoloader (included in Organization class)
# to auto-discover feature modules in this directory.

class Onetime::Organization < Familia::Horreum
  module Features
    include Familia::Features::Autoloader
  end
end
