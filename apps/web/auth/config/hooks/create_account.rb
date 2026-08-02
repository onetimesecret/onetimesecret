# apps/web/auth/config/hooks/create_account.rb
#
# frozen_string_literal: true

require 'onetime/security/create_account_rate_limiter'

#
# Account-Creation Rate Limiting (issue #3948, audit 2026-07-30 finding #4)
#
# SOLE OWNER of the before_create_account_route hook (hooks do not chain —
# see config/hooks.rb).
#
# FULL MODE ONLY: this file lives under apps/web/auth/, which the registry
# skips entirely unless auth_config.full_enabled? (lib/onetime/application/
# registry.rb#find_application_files). In simple mode — the application
# default — POST /auth/create-account is served by the Core app
# (apps/web/core/routes.txt → Core::Controllers::Registration#create_account)
# and the SAME limiter is enforced from
# AccountAPI::Logic::Account::CreateAccount#raise_concerns, with the same
# client-IP subject and the same before-any-account-lookup ordering. The two
# modes share one Redis keyspace shape and one config block, so a deployment
# gets identical protection either way. Keep the two call sites in lockstep on
# ORDERING and on the subject passed: a change here belongs there too.
#
# Production runs AUTHENTICATION_MODE=full, so THIS is the call site that
# matters for the hosted deployment; the logic-class one covers self-hosted
# simple-mode installs. Neither is redundant — only one of the two is reachable
# in a given process, because the Auth app owns /auth/* whenever it is mounted
# (Rack::URLMap dispatches longest-prefix-first, registry.rb).
#
# WHY ITS OWN FILE rather than an addition to hooks/account.rb: that file owns
# before_create_account, which is a different hook AND fires too late for this
# purpose — it runs inside the create-account POST body, after Rodauth has
# begun processing the submission. before_create_account_route fires at the top
# of the route (rodauth-2.44.0/lib/rodauth/features/create_account.rb:35),
# ahead of the db[:accounts] lookup at hooks/account.rb:67 and the
# Onetime::Customer.email_exists? call at :92, which is the
# "before any account lookup or write" ordering the limiter's header asserts.
#
# ORDERING relative to the already-logged-in guard is inherited from Rodauth
# and is the one we want: the route runs check_already_logged_in BEFORE
# before_create_account_route, so an authenticated caller is turned away
# without consuming budget. That matches the deliberate placement of the simple
# mode call site after CreateAccount#raise_concerns' authenticated check —
# a signed-in caller hitting this route is a UI mistake, not the abuse this
# bounds, and charging them would let one user's stray form posts drain a
# shared masked-IP bucket.
#
# CLIENT IP: the universal MiddlewareStack mounts Otto's IPPrivacyMiddleware
# once, which resolves the canonical env['otto.client_ip'] via the
# trusted-proxy resolver (Otto::Utils.resolve_client_ip) and rewrites
# REMOTE_ADDR to the same masked value — so neither source is spoofable via
# forwarded headers from an untrusted hop. We prefer the canonical env key and
# fall back to request.ip (the rewritten REMOTE_ADDR) when it is absent (e.g. a
# bare-Roda unit spec). An empty resolution skips the tier rather than pooling
# unknown callers into one shared bucket an attacker could poison; unlike the
# reset limiter there is no second tier to fall back on, so that is a genuine
# (small) hole — see CreateAccountRateLimiter#create_account_ip_keys.
#
# INTERNAL REQUESTS ARE EXCLUDED, EXPLICITLY. :internal_request is enabled
# (config/base.rb), and handle_internal_request runs this same route block with
# a SYNTHESIZED env whose REQUEST_METHOD is 'POST'
# (rodauth-2.44.0/lib/rodauth/features/internal_request.rb:325) — so a bare
# `request.post?` guard does NOT exclude it. The affected caller is the
# invite-signup path (Auth::Config.create_account in
# apps/api/invite/logic/invites/signup_and_accept.rb), which is already
# throttled by Onetime::Security::InviteTokenRateLimiter and is not the
# unauthenticated-flood primitive this finding targets, so it must not consume
# signup budget. We skip on internal_request? rather than leaning on the fact
# that the synthesized env carries neither otto.client_ip nor REMOTE_ADDR (the
# limiter would no-op via create_account_ip_keys returning nil): that no-op is
# an accident of the synthesized env, not a contract, and it would degrade
# SILENTLY — a future change that seeds an IP into internal requests would
# start charging invite signups against a random bucket with nothing to catch
# it.
#
# respond_to? takes the include_all argument because internal_request? is a
# PRIVATE method on the Rodauth instance (defined in features/base.rb:965 and
# overridden in the internal-request subclass); the one-argument form returns
# false for it and the guard would never fire.
#
# ENUMERATION SAFETY: the limiter keys only on the client IP — never on the
# submitted login, and never on whether it resolves to an account — so the 429
# introduces no oracle on a route whose entire response contract is that new
# and existing accounts answer identically. The raised Onetime::LimitExceeded
# propagates through around_rodauth (which re-raises typed limiter exceptions
# without the unhandled-exception error log — see overrides/error_handling.rb)
# to the router's error_handler, which renders the ADR-013 429 body with
# retry_after; Onetime::Middleware::RetryAfterHeader turns that into the RFC
# 9110 Retry-After response header.
#
# POST-only: Rodauth's route wrapper fires this hook for GET (form render) and
# POST alike; only the POST creates an account, so only the POST is counted.
#
module Auth::Config::Hooks
  module CreateAccount
    def self.configure(auth)
      # The before_create_account_route configuration method only exists when
      # :create_account is enabled (AccountManagement enables it
      # unconditionally today); same defensive guard as
      # hooks/reset_password_request.rb so a future conditional enablement
      # degrades to a no-op rather than a NoMethodError at configure time.
      auth_class = auth.instance_variable_get(:@auth)
      return unless auth_class&.features&.include?(:create_account)

      auth.auth_class_eval do
        include Onetime::Security::CreateAccountRateLimiter
      end

      auth.before_create_account_route do
        # See the INTERNAL REQUESTS note above: this must come before the
        # request.post? check, which internal requests satisfy.
        next if respond_to?(:internal_request?, true) && internal_request?

        if request.post?
          client_ip = request.env['otto.client_ip']
          client_ip = request.ip if client_ip.to_s.empty?

          enforce_create_account_rate_limit!(client_ip)
        end
      end
    end
  end
end
