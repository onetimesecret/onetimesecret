# apps/api/v2/models/customer/features.rb

class V2::Customer < Familia::Horreum
  module Features
    include Familia::Features::Autoloader
  end
end
