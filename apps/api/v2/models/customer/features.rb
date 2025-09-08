# apps/api/v2/models/customer/features.rb

# TODO: If we autoloader to check both features/ and customer/features/ paths
# we could remove this file altogether. Although it is helpful# to explicitly
# see `require_relative 'customer/features'` in the model itself. Without it,
# it's not clear how the features are loaded when getting to know the code.

class V2::Customer < Familia::Horreum
  module Features
    include Familia::Autoloader
  end
end
