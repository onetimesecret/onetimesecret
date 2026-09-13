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

      # Surface marker on remember-restored sessions (#4409). `load_memory`
      # mints its session through `login_session('remember')`, so the
      # prepended update_session override (config/overrides/surface_binding.rb)
      # records the surface of the request that PRESENTED the cookie; no
      # after_load_memory hook is needed for that.
      #
      # KNOWN LIMIT, deliberately not closed here: account_remember_keys holds
      # only (id, key, deadline), so a restore cannot check that the token is
      # being presented on the surface that ISSUED it. Browser delivery scope
      # (no `Domain` attribute, lib/onetime/application/middleware_stack.rb)
      # keeps a browser on the issuing host, but a copied token is not bound
      # server-side. Today this is inert: nothing in the app calls
      # `rodauth.load_memory`, so a remember cookie is set and never consumed.
      # Wiring it up requires binding the token to its issuing surface first
      # (a surface column on account_remember_keys, checked in
      # before_load_memory, refuse on mismatch) — see the review thread on
      # PR #4418.
    end
  end
end
