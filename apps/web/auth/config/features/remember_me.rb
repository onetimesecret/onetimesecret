# apps/web/auth/config/features/remember_me.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Remember me feature: persistent login across browser sessions.
  # Provides the "Remember me" checkbox on the login form.
  #
  # ENV: AUTH_REMEMBER_ME_ENABLED (default: enabled, set to 'false' to disable)
  #
  module RememberMe
    def self.configure(auth)
      auth.enable :remember

      # Remember cookie settings are inherited from Rodauth defaults:
      # - remember_cookie_key: '_remember'
      # - remember_deadline_interval: 14 days
      # - extend_remember_deadline?: false

      # Stamp the surface marker on remember-restored sessions (#4409).
      # `after_login` does not fire for remember restoration — Rodauth calls
      # `login_session('remember')` directly from `load_memory` — so without
      # this hook a restored session would carry no marker and the enforcement
      # gate would refuse it on the very next request.
      #
      # The remember cookie is delivered only to the host that set it (no
      # `Domain` attribute, per lib/onetime/application/middleware_stack.rb),
      # so a successful restore is by construction happening on the surface
      # where the original login occurred. Recording the current request's
      # surface therefore matches that establishing surface. Any subsequent
      # request whose surface differs will then be refused by the gate, as
      # it would be for a fresh login.
      auth.after_load_memory do
        Onetime::SessionSurface.record(session, request.env)
      end
    end
  end
end
