# apps/web/auth/config/overrides/surface_binding.rb
#
# frozen_string_literal: true

module Auth::Config::Overrides
  # Surface-bound sessions (#4409): stamp the establishing surface at the ONE
  # seam every Rodauth login path shares.
  #
  # Rodauth mints an authenticated session through `login_session`, which
  # calls `update_session` (base.rb). `after_login` fires only for the
  # `login` route family (password, email-auth, WebAuthn, OmniAuth); the
  # autologins do NOT run it: `create_account` (`create_account_autologin?`,
  # the invite-signup path), `verify_account` (`verify_account_autologin?`,
  # Rodauth default TRUE, so every fresh signup that verifies by email lands
  # here), `reset_password` (`reset_password_autologin?`), and the remember
  # feature's `load_memory` all call `login_session` directly. Stamping in
  # `after_login` alone left those sessions markerless, and the fail-closed
  # gate (auth router, BaseSessionAuthStrategy, SessionHelpers) refused them
  # on the very next request.
  #
  # Prepended rather than defined with `def update_session` in
  # `auth_class_eval`: Rodauth's auth class is one class, so a second `def`
  # of the same name REPLACES the active-sessions override
  # (features/active_sessions.rb) instead of chaining with it. A prepended
  # module sits ahead of the class's own definition and reaches it through
  # `super`, so both stamps run and neither file has to know about the other.
  #
  # Internal requests (`Auth::Config.valid_login_and_password?`,
  # `internal_request_eval`) run against a bare Hash session and an env that
  # DomainStrategy never saw; there is no surface to record there, and the
  # caller that merges such a session into a real Rack session (invite
  # signup, apps/api/invite/logic/invites/signup_and_accept.rb) stamps from
  # its own request context. Skipped explicitly rather than stamping nil so
  # the marker key is never present-but-nil.
  module SurfaceBinding
    module UpdateSession
      def update_session
        super
        return if respond_to?(:internal_request?, true) && internal_request?

        Onetime::SessionSurface.record(session, request.env)
      end
    end

    def self.configure(auth)
      auth.auth_class_eval { prepend Auth::Config::Overrides::SurfaceBinding::UpdateSession }
    end
  end
end
