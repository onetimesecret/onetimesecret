# apps/api/v2/logic/authentication.rb

require_relative 'base'

module V2::Logic
  module Authentication
    class AuthenticateSession < V1::Logic::Authentication::AuthenticateSession
    end

    class ResetPasswordRequest < V1::Logic::Authentication::ResetPasswordRequest
    end

    class ResetPassword < V1::Logic::Authentication::ResetPassword
    end

    class DestroySession < V1::Logic::Authentication::DestroySession
    end
  end
end
