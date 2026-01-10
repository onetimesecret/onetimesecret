# apps/web/auth/config/features/active_sessions.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Active sessions feature: track and manage user sessions across devices.
  # Allows users to view where they're logged in and revoke sessions.
  #
  # ENV: ENABLE_ACTIVE_SESSIONS (default: enabled, set to 'false' to disable)
  #
  module ActiveSessions
    def self.configure(auth)
      auth.enable :active_sessions

      # Session lifetime settings
      #
      # Enables updating last_use timestamp on each request where
      # currently_active_session? is checked.
      #
      auth.session_inactivity_deadline 86_400   # 24 hours - sessions inactive for this long are removed
      auth.session_lifetime_deadline 2_592_000  # 30 days - max session lifetime
    end
  end
end
