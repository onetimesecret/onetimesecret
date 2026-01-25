# lib/onetime/models/receipt/features.rb
#
# frozen_string_literal: true

# Receipt features loader
# Uses Familia::Features::Autoloader (included in Receipt class)
# to auto-discover feature modules in this directory.

class Onetime::Receipt < Familia::Horreum
  module Features
    include Familia::Features::Autoloader
  end
end
