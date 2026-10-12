# apps/web/auth/config/hooks/email_login_request.rb
#
# frozen_string_literal: true

require 'onetime/security/reset_request_rate_limiter'
require_relative '../../lib/public_host'

#
# Email-Login-Request Preflight (rate limiting, RISK-2026-08-14-M04)
#
# SOLE OWNER of the before_email_auth_request_route hook (hooks do not chain —
# see config/hooks.rb). Not to be confused with before_email_auth_request,
# which restrict_to.rb owns and which fires later, inside _email_auth_request.
#
# FULL MODE AND EMAIL_AUTH ONLY: the route exists only when the :email_auth
# feature is enabled (AUTH_EMAIL_AUTH_ENABLED), so config.rb configures this
# inside the email_auth block. Simple mode has no magic-link route.
#
# POST /auth/email-login-request had no limiter of its own: Rodauth's resend
# window (email_auth_skip_resend_email_within, 30s here) caps emails per
# ACCOUNT, not requests per source, so one origin could mail a link to every
# address it cared to name (mailbox bombing) and sample the enumeration-safe
# route (config/overrides/login_request_enumeration.rb) as fast as it liked —
# that override accepts a statistical TIMING residual which many samples
# expose. This hook enforces Onetime::Security::ResetRequestRateLimiter under
# its :email_login_request scope — a per-client-IP tier plus a
# per-submitted-login backstop, same tiers and normalization as the
# reset-request limiter, separate keys, config block and audit verb — BEFORE
# the route body runs, i.e. before Rodauth's account lookup. A throttled probe
# never reaches the timing-sensitive path at all.
#
# CLIENT IP: same resolution as hooks/reset_password_request.rb — prefer the
# canonical env['otto.client_ip'] (IPPrivacyMiddleware, trusted-proxy aware,
# privacy-masked), fall back to request.ip. An empty resolution skips the IP
# tier rather than pooling unknown callers into one bucket; the per-login
# backstop still applies.
#
# ENUMERATION SAFETY: the limiter keys only on request-observable inputs (IP,
# submitted login string), never on account existence, and it runs before the
# lookup, so the 429 is the same for an existing and a non-existent login. The
# raised Onetime::LimitExceeded propagates through around_rodauth (which
# re-raises typed limiter exceptions; overrides/error_handling.rb) to the
# router's error_handler, which renders the ADR-013 429 body with retry_after.
#
# After rate limiting, require an allowlisted origin before account lookup,
# as the reset hook does. Every email link is built from that origin
# (config/overrides/public_base_url.rb), so with none configured a real
# account's request fails while a missing login's request — answered by the
# enumeration override before any link is built — would not. Checking first
# makes that failure the same for every login.
#
# INTERNAL REQUESTS are skipped, as in hooks/create_account.rb: Rodauth's
# internal_request runs this route block with a synthesized POST env, and a
# server-initiated request is not the anonymous volume this bounds (no caller
# today; the guard keeps a future one from consuming a visitor's budget).
# respond_to? takes include_all because internal_request? is private.
#
# POST-only: Rodauth's route wrapper fires this hook for GET (form render) and
# POST alike; only the POST performs the account lookup + email dispatch.
#
# THE LOGIN ROUTE mails links too: with :email_auth loaded, POST /auth/login
# with a login and no password sends one to a passwordless account (Rodauth
# login.rb, after_login_entered_during_multi_phase_login) without entering
# this route, so the hook above never sees it. charge_login_dispatch! charges
# that dispatch to the same budget; see its comment.
#
module Auth::Config::Hooks
  module EmailLoginRequest
    def self.configure(auth)
      # The before_email_auth_request_route configuration method only exists
      # when :email_auth is enabled. config.rb calls this inside the
      # email_auth block; the guard keeps a misplaced call a no-op rather than
      # a NoMethodError at configure time.
      auth_class = auth.instance_variable_get(:@auth)
      return unless auth_class&.features&.include?(:email_auth)

      auth.auth_class_eval do
        include Onetime::Security::ResetRequestRateLimiter
      end

      auth.before_email_auth_request_route do
        next if respond_to?(:internal_request?, true) && internal_request?

        if request.post?
          Auth::Config::Hooks::EmailLoginRequest.charge!(self)
          # Account-independent host preflight (see header).
          Auth::PublicHost.required_base_url!(request.env)
        end
      end
    end

    # Charges the magic link the LOGIN route sends (see header) to the
    # :email_login_request budget. restrict_to.rb owns before_email_auth_request,
    # the one hook every dispatch passes, and calls this after its host gates.
    #
    # Unlike the route hook this runs after the account lookup, since only a
    # passwordless account gets here. That adds no oracle: the login route
    # already answers a missing login differently. An account mailed within
    # Rodauth's resend window is answered before this hook, so the budget
    # counts mails about to be sent.
    def self.charge_login_dispatch!(rodauth)
      # The dedicated route's own hook already charged this request.
      return if rodauth.current_route == :email_auth_request
      return if rodauth.send(:internal_request?)

      charge!(rodauth)
    end

    # One charge per client IP, then per submitted login (header: CLIENT IP).
    def self.charge!(rodauth)
      request   = rodauth.request
      client_ip = request.env['otto.client_ip']
      client_ip = request.ip if client_ip.to_s.empty?

      rodauth.enforce_email_login_request_rate_limit!(client_ip, rodauth.param_or_nil(rodauth.login_param))
    end
  end
end
