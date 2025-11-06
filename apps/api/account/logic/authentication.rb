# apps/api/account/logic/authentication.rb

require_relative 'base'

module AccountAPI
  module Logic
    module Authentication
    end
  end
end

require_relative 'authentication/reset_password_request'
require_relative 'authentication/reset_password'
require_relative 'authentication/destroy_session'
