# apps/api/account/logic/account.rb
#
# frozen_string_literal: true

require_relative 'base'

module AccountAPI
  module Logic
    module Account
      using Familia::Refinements::TimeLiterals

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
