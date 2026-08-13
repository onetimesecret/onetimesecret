# apps/web/auth/config/hooks/restrict_to.rb
#
# frozen_string_literal: true

#
# Rodauth wiring for restrict_to enforcement
# (ADR-034#restrict-to-is-an-access-control-not-a-display-preference
# / #reject-as-not-found-not-forbidden, issue #4139).
#
# The POLICY — the route → sign-in-method table, resolution input gathering,
# and the 404 reject shape — lives in apps/web/auth/restrict_to.rb
# (Auth::RestrictTo), because it also has non-Rodauth callers that must not be
# forced to load anything under config/. This file is only the hook
# registration. See that file's header for the rationale and for the two other
# surfaces (OmniAuth, simple mode) that this hook cannot reach.
#
# MECHANISM: before_rodauth fires inside the matched route, after
# @current_route is set and after CSRF has been checked. It is the one hook
# that runs for EVERY route, so it must stay cheap and must never be redefined
# elsewhere (hooks do not chain — see config/hooks.rb).
#

require_relative '../../restrict_to'

module Auth::Config::Hooks
  module RestrictTo
    def self.configure(auth)
      auth.before_rodauth do
        Auth::RestrictTo.enforce_route!(self)
      end
    end

    # SECONDARY email_auth surface that is NOT its own route: with the
    # email_auth feature loaded, `use_multi_phase_login?` is true, so a POST to
    # the LOGIN route for a passwordless account reaches
    # `after_login_entered_during_multi_phase_login` and dispatches a magic link
    # (`force_email_auth?`). The login route is gated on 'password', so on a
    # password-restricted host that path would still emit an email_auth
    # credential. This hook closes it at the one chokepoint both entry points
    # share.
    #
    # Registered separately because `before_email_auth_request` only EXISTS as a
    # configuration method when the email_auth feature is loaded — see the call
    # site in config.rb, inside the email_auth_enabled? branch.
    def self.configure_email_auth(auth)
      auth.before_email_auth_request do
        Auth::RestrictTo.enforce_method!(self, 'email_auth', :email_auth_request)
      end
    end
  end
end
