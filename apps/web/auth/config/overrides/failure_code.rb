# apps/web/auth/config/overrides/failure_code.rb
#
# frozen_string_literal: true

#
# MECHANISM: method override — `auth.set_error_reason` REPLACES Rodauth's
# (empty) implementation, the same way password_migration.rb replaces
# password_match?. It is not a before/after hook.
#
# Rodauth calls set_error_reason(reason) from throw_error_reason and
# set_response_error_reason_status on every route it serves, immediately
# before it renders the error response. That makes it the single seam
# through which a Rodauth refusal reaches the stable `code` / `code_scope`
# pair (#4469): the policy in Auth::CredentialFailureCode decides whether the
# reason is a rejected credential, a session refusal, or neither, and
# Onetime::Middleware::SessionFailureCode renders the result onto the 401.
# No route, hook, or feature file needs to know about it.
#

require_relative '../../credential_failure_code'

module Auth::Config::Overrides
  module FailureCode
    def self.configure(auth)
      auth.set_error_reason do |reason|
        super(reason)
        Auth::CredentialFailureCode.record(request.env, reason)
      end
    end
  end
end
