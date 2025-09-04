# apps/api/v2/models/secret/features.rb

class V2::Secret < Familia::Horreum
  module Features
    include Familia::Features::Autoloader
  end
end
