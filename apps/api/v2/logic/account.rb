# apps/api/v2/logic/account.rb

require_relative 'base'

module V2
  module Logic
    module Account
    end
  end
end

require_relative 'account/create_account'
require_relative 'account/destroy_account'
require_relative 'account/generate_api_token'
require_relative 'account/get_account'
require_relative 'account/update_account_field'
require_relative 'account/update_password'
require_relative 'account/update_locale'
