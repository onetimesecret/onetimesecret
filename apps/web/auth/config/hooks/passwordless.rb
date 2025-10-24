# apps/web/auth/config/hooks/passwordless.rb

#
# This file defines the Rodauth hooks related to user authentication
# by email link (aka Passwordless, aka Magic Link).
#

module Auth::Config::Hooks
  module Passwordless
    def self.configure(auth)
      #
      #
      # Hook: Before handling email auth route (form submission)
      auth.before_email_auth_route do
        SemanticLogger['Auth'].debug 'Processing magic link authentication'
        # No arguments are passed to the block.
        # You can access request parameters using Rodauth methods like 'param'.
        auth_token = param('key')

        if auth_token.nil? || auth_token.empty?
          msg = 'The email authentication token is missing.'
          SemanticLogger['Auth'].error msg
          set_error_flash msg
          redirect login_path
        end
      end

      # Hook: After sending magic link email
      auth.after_email_auth_request do
        SemanticLogger['Auth'].info 'Magic link email sent',
          account_id: account[:id],
          email: account[:email]

        # NOTE: Successful login is tracked via session middleware
        # Set session values in base after_login hook
      end
    end
  end
end
