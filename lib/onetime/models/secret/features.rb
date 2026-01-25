# lib/onetime/models/secret/features.rb
#
# frozen_string_literal: true

# An example of a features.rb with the autoloader

class Onetime::Secret < Familia::Horreum
  module Features
    include Familia::Features::Autoloader
  end
end
