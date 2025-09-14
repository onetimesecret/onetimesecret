# lib/onetime/models/secret/features.rb

# An example of a features.rb with the autoloader

class V2::Secret < Familia::Horreum
  module Features
    include Familia::Features::Autoloader
  end
end
