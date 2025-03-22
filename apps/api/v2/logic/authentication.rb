# apps/api/v2/logic/authentication.rb

require_relative 'base'
require_relative 'authentication/authenticate_session'
require_relative 'authentication/reset_password_request'
require_relative 'authentication/reset_password'
require_relative 'authentication/destroy_session'

module V2::Logic
  module Authentication
  end
end
