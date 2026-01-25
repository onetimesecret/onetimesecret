# lib/onetime/models/custom_domain/features.rb
#
# frozen_string_literal: true

# CustomDomain features loader
# Uses Familia::Features::Autoloader (included in CustomDomain class)
# to auto-discover feature modules in this directory.

class Onetime::CustomDomain < Familia::Horreum
  module Features
    include Familia::Features::Autoloader
  end
end
