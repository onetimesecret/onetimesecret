# apps/web/auth/config/hooks/email_auth_request.rb
#
# frozen_string_literal: true

require 'onetime/security/email_auth_rate_limiter'

#
# Magic-Link Request Rate Limiting (audit 2026-08-02 finding L-5)
#
# SOLE OWNER of the before_email_auth_request_route hook (hooks do not chain —
# see config/hooks.rb).
#
# WHY ITS OWN FILE rather than an addition to hooks/email_auth.rb: that file
# owns before_email_auth_route and after_email_auth_request, which are
# DIFFERENT hooks on the redemption side of the flow — before_email_auth_route
# fires when the user clicks the link (GET/POST /auth/email-login), and
# after_email_auth_request fires inside _email_auth_request's transaction,
# after account_from_login has already succeeded. Neither can enforce this
# limit: the redemption route is not the mail-dispatch primitive the finding
# targets, and the request-side hook fires only for EXISTING accounts, so
# enforcing there would key throttling on registration state — an enumeration
# oracle. before_email_auth_request_route fires at the top of the request
# route (rodauth-2.42.0/lib/rodauth/features/email_auth.rb:56), ahead of the
# account_from_login lookup and the email_auth key INSERT + send, which is the
# "before any account lookup or write" ordering the limiter's header asserts.
#
# FULL MODE IS THE WHOLE SURFACE: this file lives under apps/web/auth/, which
# the registry skips unless auth_config.full_enabled? — and unlike
# create-account there is no simple-mode counterpart route to protect. In
# simple mode GET /email-login (apps/web/core/routes.txt) renders the SPA
# page; the POST it would submit to does not exist, so there is no second call
# site to keep in lockstep.
#
# ORDERING relative to the already-logged-in guard is inherited from Rodauth
# and is the one we want: the route runs check_already_logged_in BEFORE
# before_email_auth_request_route, so an authenticated caller is turned away
# without consuming budget. A signed-in caller hitting this route is a UI
# mistake, not the abuse this bounds, and charging them would let one user's
# stray form posts drain a shared masked-IP bucket.
#
# CLIENT IP: the universal MiddlewareStack mounts Otto's IPPrivacyMiddleware
# once, which resolves the canonical env['otto.client_ip'] via the
# trusted-proxy resolver (Otto::Utils.resolve_client_ip) and rewrites
# REMOTE_ADDR to the same masked value — so neither source is spoofable via
# forwarded headers from an untrusted hop. We prefer the canonical env key and
# fall back to request.ip (the rewritten REMOTE_ADDR) when it is absent (e.g.
# a bare-Roda unit spec). An empty resolution skips the tier rather than
# pooling unknown callers into one shared bucket an attacker could poison —
# see EmailAuthRateLimiter#email_auth_ip_keys.
#
# INTERNAL REQUESTS ARE EXCLUDED, EXPLICITLY. :internal_request is enabled
# (config/base.rb) and the email_auth feature registers
# internal_request_method :email_auth_request, which runs this same route
# block with a SYNTHESIZED env whose REQUEST_METHOD is 'POST' — so a bare
# `request.post?` guard does NOT exclude it. No code path calls it today, but
# leaning on the synthesized env carrying no IP (the limiter would no-op via
# email_auth_ip_keys returning nil) would degrade SILENTLY — a future change
# that seeds an IP into internal requests would start charging server-side
# callers against a random bucket with nothing to catch it.
#
# respond_to? takes the include_all argument because internal_request? is a
# PRIVATE method on the Rodauth instance; the one-argument form returns false
# for it and the guard would never fire.
#
# ENUMERATION SAFETY: the limiter keys only on the client IP — never on the
# submitted login, and never on whether it resolves to an account — so the 429
# introduces no registration-state oracle. Requests for unknown addresses DO
# cost budget: they are free to generate, and a limiter that only counted
# successful sends would leak registration state through its own bookkeeping.
# The raised Onetime::LimitExceeded propagates to the auth router's error
# handler, which Auth::ErrorTranslator maps to a 429 with retry_after.
#
# ADDITIVE: Rodauth's email_auth_skip_resend_email_within (per-account resend
# throttle, config/features/email_auth.rb) stays — it bounds resends per
# mailbox; this bounds cross-address volume per origin. Neither replaces the
# other.
#
# POST-only: Rodauth's route wrapper fires this hook for GET (form render) and
# POST alike; only the POST dispatches mail, so only the POST is counted.
#
module Auth::Config::Hooks
  module EmailAuthRequest
    def self.configure(auth)
      # The before_email_auth_request_route configuration method only exists
      # when :email_auth is enabled — which config.rb guarantees at the call
      # site (this configure runs inside the email_auth_enabled? branch).
      # Defensive guard anyway, so a future unconditional registration
      # degrades to a no-op rather than a NoMethodError at configure time.
      auth_class = auth.instance_variable_get(:@auth)
      return unless auth_class&.features&.include?(:email_auth)

      auth.auth_class_eval do
        include Onetime::Security::EmailAuthRateLimiter
      end

      auth.before_email_auth_request_route do
        # See the INTERNAL REQUESTS note above: this must come before the
        # request.post? check, which internal requests satisfy.
        next if respond_to?(:internal_request?, true) && internal_request?

        if request.post?
          client_ip = request.env['otto.client_ip']
          client_ip = request.ip if client_ip.to_s.empty?

          enforce_email_auth_rate_limit!(client_ip)
        end
      end
    end
  end
end
