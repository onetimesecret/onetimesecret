# apps/web/auth/config/features/remember_me.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Remember me feature: persistent login across browser sessions.
  # Provides the "Remember me" checkbox on the login form.
  #
  # ENV: ENABLE_REMEMBER_ME (default: enabled, set to 'false' to disable)
  #
  module RememberMe
    def self.configure(auth)
      auth.enable :remember

      # Remember cookie settings are inherited from Rodauth defaults:
      # - remember_cookie_key: '_remember'
      # - remember_deadline_interval: 14 days
      # - extend_remember_deadline?: false
    end
  end
end
