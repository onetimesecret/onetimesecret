# apps/web/auth/config/hooks/restrict_to.rb
#
# frozen_string_literal: true

#
# Rodauth wiring for restrict_to enforcement
# (ADR-034#restrict-to-is-an-access-control-not-a-display-preference
# / #reject-as-not-found-not-forbidden, issue #4139).
#
# This file registers BOTH pre-auth gates, because before_rodauth can only be
# defined once (hooks do not chain): the restrict_to axis (Auth::RestrictTo)
# and the ADR-024 sign-in/sign-up opt-in axis (Auth::SigninGate, #4163).
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

# WHY THIS FILE OWNS TWO GATES
#
# `before_rodauth` and `before_email_auth_request` are SINGLY OWNED: Rodauth
# hooks do not chain, so a second `auth.before_rodauth do ... end` anywhere
# would REPLACE this one rather than run alongside it (config/hooks.rb states
# the rule; config.rb's hook list is a precedence list for exactly this
# reason). The per-domain `signin_enabled` availability gate
# (Auth::SigninEnabled, ADR-024) needs the same two chokepoints, so it is
# invoked from inside these blocks instead of registering its own. Its POLICY
# lives in its own sibling module beside apps/web/auth/restrict_to.rb; only the
# call sites are shared.
#
# THE TWO GATES ARE DIFFERENT QUESTIONS AND ARE ANDed, NOT MERGED:
#   Auth::SigninEnabled — IS password/email sign-in available on this host at
#     all? Defaults CLOSED on custom domains (ADR-024 opt-in only).
#   Auth::RestrictTo    — GIVEN that it is, WHICH methods may be offered?
#     Defaults OPEN; an absence of restriction gates nothing, by invariant.
# Collapsing either into the other is the #4139 shape — see the header of
# apps/web/auth/signin_enabled.rb.

require_relative '../../restrict_to'
require_relative '../../signin_gate'

module Auth::Config::Hooks
  module RestrictTo
    def self.configure(auth)
      auth.before_rodauth do
        # Availability first, then method narrowing: a host that is not
        # offering password/email sign-in at all has no method question to
        # answer. Both reject with the same 404 body, so the order is not
        # observable — it is written this way to read in policy order.
        Auth::SigninEnabled.enforce_route!(self)
        Auth::RestrictTo.enforce_route!(self)
        # SECOND AXIS, same hook (#4163). restrict_to says WHICH sign-in method
        # a host may offer; Auth::SigninGate says whether the host opted into
        # sign-in / sign-up at all (ADR-024). Hooks do not chain, so both must
        # be driven from this one registration.
        #
        # ORDER IS LOAD-BEARING ONLY IN ONE DIRECTION: the reject bodies are
        # byte-identical, so neither order leaks which gate fired, but
        # restrict_to runs first so the narrower method-level verdict is the one
        # that stands where both apply.
        Auth::SigninGate.enforce_route!(self)
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
    # BOTH AXES hang here, for the same reason they both hang on before_rodauth:
    # the restrict_to gate answers "may this host offer magic links as a METHOD"
    # and Auth::SigninGate answers "did this host opt into sign-in at all, and
    # is email_auth effective for it" (SigninConfig.resolve_email_auth_enabled).
    # before_rodauth cannot cover this path — it sees route :login and applies
    # only the plain sign-in axis, so leaving SigninGate off this hook leaves a
    # host that disabled magic links still sending them.
    #
    # Registered separately because `before_email_auth_request` only EXISTS as a
    # configuration method when the email_auth feature is loaded — see the call
    # site in config.rb, inside the email_auth_enabled? branch.
    def self.configure_email_auth(auth)
      auth.before_email_auth_request do
        # Same pairing as before_rodauth above, and needed for the same reason:
        # this path emits an email_auth credential from the LOGIN route, so a
        # host that never opted into sign-in (ADR-024 default-OFF) would
        # otherwise still get a magic link mailed on its behalf.
        Auth::SigninEnabled.enforce!(self, :email_auth_request)
        Auth::RestrictTo.enforce_method!(self, 'email_auth', :email_auth_request)
        Auth::SigninGate.enforce_email_auth!(self)
      end
    end
  end
end
