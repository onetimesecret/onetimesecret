# apps/web/auth/config/hooks/reset_password_request.rb
#
# frozen_string_literal: true

require 'onetime/security/reset_request_rate_limiter'

#
# Reset-Password-Request Rate Limiting (issue #3872)
#
# SOLE OWNER of the before_reset_password_request_route hook (hooks do not
# chain — see config/hooks.rb).
#
# FULL MODE ONLY: this file lives under apps/web/auth/, which the registry
# skips entirely unless auth_config.full_enabled? (lib/onetime/application/
# registry.rb#find_application_files). In simple mode — the application
# default — POST /auth/reset-password-request is served by the Core app
# (apps/web/core/routes.txt → Core::Controllers::Registration#request_reset_email)
# and the SAME limiter is enforced from
# AccountAPI::Logic::Authentication::ResetPasswordRequest#raise_concerns, with
# the same client-IP subject and the same before-any-account-lookup ordering.
# The login subject differs by construction — each mode passes the string IT
# resolves accounts with (normalize_login here, sanitize_email there) — which is
# what keeps each mode's buckets 1:1 with its own lookup; see the limiter header.
# Keep the two call sites in lockstep on ORDERING and on which subjects are
# passed: a change to that here belongs there too.
#
# The enumeration override (config/overrides/reset_password_enumeration.rb,
# #3857) made every POST /auth/reset-password-request answer identically, which
# closed the single-request content oracle but accepted a statistical TIMING
# residual. Exploiting that residual needs many samples per target; this hook
# caps that throughput by enforcing Onetime::Security::ResetRequestRateLimiter
# (per-client-IP tight tier + per-submitted-login backstop) BEFORE the route
# body runs — i.e. before Rodauth's account lookup, so a throttled probe never
# executes the timing-sensitive path at all. It stacks with Rodauth's own
# resend throttle, which caps emails per account but not request volume per
# source (#3857 preserved it).
#
# CLIENT IP: the universal MiddlewareStack mounts Otto's IPPrivacyMiddleware
# once, which resolves the canonical env['otto.client_ip'] via the
# trusted-proxy resolver (Otto::Utils.resolve_client_ip) and rewrites
# REMOTE_ADDR to the same masked value — so neither source is spoofable via
# forwarded headers from an untrusted hop. We prefer the canonical env key and
# fall back to request.ip (the rewritten REMOTE_ADDR) when it is absent (e.g. a
# bare-Roda unit spec). An empty resolution skips the IP tier rather than
# pooling unknown callers into one shared bucket an attacker could poison —
# the per-login backstop still applies (same reasoning as the
# sso_link_confirm throttle subject and LoginRateLimiter's RL-3 note).
#
# ENUMERATION SAFETY: the limiter keys only on request-observable inputs (IP,
# submitted login string), never on account existence, so the 429 introduces
# no new oracle. The raised Onetime::LimitExceeded propagates through
# around_rodauth (which re-raises typed limiter exceptions without the
# unhandled-exception error log — see overrides/error_handling.rb) to the
# router's error_handler, which renders the ADR-013 429 body with retry_after.
#
# POST-only: Rodauth's route wrapper fires this hook for GET (form render)
# and POST alike; only the POST performs the account lookup + email dispatch
# that the timing channel rides on, so only the POST is counted.
#
module Auth::Config::Hooks
  module ResetPasswordRequest
    def self.configure(auth)
      # The before_reset_password_request_route configuration method only
      # exists when :reset_password is enabled (AccountManagement enables it
      # unconditionally today); same defensive guard as the enumeration
      # override so a future conditional enablement degrades to a no-op
      # rather than a NoMethodError at configure time.
      auth_class = auth.instance_variable_get(:@auth)
      return unless auth_class&.features&.include?(:reset_password)

      auth.auth_class_eval do
        include Onetime::Security::ResetRequestRateLimiter
      end

      auth.before_reset_password_request_route do
        if request.post?
          client_ip = request.env['otto.client_ip']
          client_ip = request.ip if client_ip.to_s.empty?

          enforce_reset_request_rate_limit!(client_ip, param_or_nil(login_param))
        end
      end
    end
  end
end
