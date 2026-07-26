# lib/onetime/middleware/instrumented_authenticity_token.rb
#
# frozen_string_literal: true

require 'rack/protection'

module Onetime
  module Middleware
    ##
    # InstrumentedAuthenticityToken
    #
    # Rack::Protection::AuthenticityToken that stamps a private env marker on the
    # exact rejection path, so CsrfResponseHeader can tell a genuine CSRF 403
    # apart from an app-level 403 (Onetime::Forbidden, EntitlementRequired,
    # GuestRoutesDisabled) it merely wraps. See #3837 (root cause of #3831).
    #
    # Why a subclass and not rack-protection's :instrumenter hook:
    #   The instrumenter fires from Base#call for ANY reaction (including
    #   :report) BEFORE the reaction runs, so its env['rack.protection.attack']
    #   marker means "attack detected", not "request denied". Wiring up a no-op
    #   instrumenter purely to trigger that side effect also couples us to an
    #   internal detail (the marker string derived from self.class.name...downcase).
    #   Overriding #deny instead gives us our OWN key/value on the one path that
    #   actually returns a 403 — the marker now means "denied", and we own it.
    #
    # Why `default_reaction :deny` is REQUIRED, not decorative:
    #   base.rb runs `alias default_reaction deny` at class-definition time, which
    #   snapshots Base#deny's method body. Rejection dispatches via
    #   `send(options[:reaction], env)` where the default reaction is
    #   :default_reaction — i.e. that frozen alias, NOT the name #deny. A plain
    #   override of #deny would therefore be dead code: dispatch would still reach
    #   Base#deny's snapshot and our marker would never be set. The class macro
    #   `self.default_reaction` (base.rb) re-aliases :default_reaction to our
    #   override, so both the default dispatch and an explicit `reaction: :deny`
    #   route through the method below. A live-stack integration test
    #   (spec/integration/all/csrf_enforcement_spec.rb) guards this invariant: if
    #   rack-protection ever changes the dispatch, that test goes red rather than
    #   silently mislabeling 403s.
    class InstrumentedAuthenticityToken < Rack::Protection::AuthenticityToken
      # Rack env key stamped true when this middleware denies a request. The env
      # hash is the same object all the way up the middleware chain, so
      # CsrfResponseHeader reads this after @app.call returns. Namespaced under
      # `onetime.` per the app's custom-env-key convention (onetime.nonce, etc.).
      REJECTION_ENV_KEY = 'onetime.csrf.rejected'

      # Runs ONLY on rejection (the deny reaction). Stamps our marker, then
      # delegates to Base#deny for the standard 403 response tuple.
      def deny(env)
        env[REJECTION_ENV_KEY] = true
        super
      end

      # Rebind Base's stale `default_reaction` alias to the override above.
      default_reaction :deny
    end
  end
end
