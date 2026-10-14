# apps/web/auth/config/overrides/login_request_enumeration.rb
#
# frozen_string_literal: true

#
# Login-Request Enumeration Safety (issue #3857, RISK-2026-08-14-M03)
#
# One answer, whatever the account state, on the three unauthenticated routes
# that take a login and mail a link to it:
#
#   POST /auth/reset-password-request   (:reset_password, always enabled)
#   POST /auth/email-login-request      (:email_auth, AUTH_EMAIL_AUTH_ENABLED)
#   POST /auth/verify-account-resend    (:verify_account, AUTH_VERIFY_ACCOUNT_ENABLED)
#
# MECHANISM: method overrides via `auth_class_eval` — these REPLACE Rodauth
# methods (overrides clobber like hooks do: last definition wins), which is why
# this file lives in config/overrides/ rather than config/hooks/. `super` inside
# each override invokes the stock Rodauth implementation (features are included
# as modules, so the originals live in the class's ancestry).
#
# ONE account_from_login FOR ALL THREE ROUTES. account_from_login is shared by
# every route that takes a login, and a second definition anywhere would
# silently replace this one. It therefore dispatches on current_route (set by
# Rodauth's route wrapper) and acts only on the three routes above; on every
# other route — login above all — a missing account behaves exactly as stock
# Rodauth. Internal requests bypass the wrapper, leaving current_route nil, so
# they are unaffected too: AccountAPI::Logic::Account::ResendVerifyAccount
# relies on Auth::Config.verify_account_resend still RAISING for a missing,
# verified or throttled login.
#
# Each route only exists when its feature is enabled, so a route's branch is
# inert otherwise. The per-feature predicate overrides further down call
# `super` into the feature module and are therefore DEFINED only when
# `auth_class.features` includes that feature. Rodauth fills `features` as each
# `enable` runs, so config.rb must call configure AFTER the email_auth block —
# called earlier, the email_auth overrides are skipped and its oracle returns.
#
# WHY THIS EXISTS
# ---------------
# In `full` auth mode the Rodauth app is mounted at `/auth` and — because
# Rack::URLMap dispatches to the longest matching prefix — handles EVERY
# `/auth/*` route. These routes are therefore the ones actually exposed to
# unauthenticated callers; POST /auth/reset-password-request shadows the
# enumeration-safe custom endpoint in apps/web/core (mounted at `/`).
#
# Stock Rodauth 2.45.0 answers "account exists" and "no account" differently on
# each route, an account-existence oracle (CWE-204):
#
#   reset_password_request (lib/rodauth/features/reset_password.rb):
#     1. no matching login         -> throw_error_reason(:no_matching_login, ...)
#     2. account not open/verified -> reset_password_request_for_unverified_account
#                                     (throws :unverified_account)
#     3. email recently sent       -> "reset_password_email_recently_sent" error
#
#   email_auth_request (lib/rodauth/features/email_auth.rb, route and
#   _email_auth_request):
#     1. no matching login         -> 401 no_matching_login + request error
#     2. account not open          -> the same 401 (unverified accounts are
#                                     found by _account_from_login; closed
#                                     ones are not, so they take branch 1)
#     3. email recently sent       -> "email_auth_email_recently_sent" error
#                                     (400)
#
#   verify_account_resend (lib/rodauth/features/verify_account.rb):
#     1. no matching login         -> 401 no_matching_login + resend error
#     2. account already verified  -> the same 401
#        (!allow_resending_verify_account_email?)
#     3. email recently sent       -> "verify_account_email_recently_sent"
#                                     error (400)
#     4. unverified, no key row    -> the same 401 (verify_account_email_resend
#                                     returns nil)
#
# A registered, eligible account returns 200 { success: "..." }, whereas the
# branches above return an error status and body. Comparing the two lets an
# unauthenticated caller enumerate accounts — exactly the posture the custom
# reset endpoint (apps/api/account/logic/authentication/reset_password_request.rb)
# and the uniform resend endpoint
# (apps/api/account/logic/account/resend_verify_account.rb) were written to
# prevent.
#
# WHY OVERRIDE RATHER THAN DISABLE THE ROUTES
# -------------------------------------------
# The consume paths (`/auth/reset-password`, `/auth/email-login`,
# `/auth/verify-account`) are Rodauth's and expect Rodauth-generated keys, and
# the emails link to Rodauth's URLs (config/email/*.rb) — so the request paths
# must remain Rodauth's to mint those keys. Instead we neutralise every oracle
# branch so each POST yields the SAME generic "email sent" response the route's
# success path gives, regardless of whether the login maps to an account,
# whether that account is eligible, and whether an email was recently sent.
#
# Side effects (key creation + email) still happen only for an existing,
# eligible, non-throttled account, and Rodauth's resend throttles are
# PRESERVED: a recently-emailed account returns the same generic success
# WITHOUT resending, so closing the oracle does not open an email-bombing
# regression.
#
# RECIPIENT CREDENTIAL ORIGIN (the same oracle, one step later)
# --------------------------------------------------------------
# An eligible account's email link is built from base_url, which raises
# Auth::PublicHost::MissingAllowlistedOrigin when the recipient has neither a
# tenant nor a canonical credential origin (a verified tenant host with no
# site.host). A missing login never builds a link, so unguarded that 500 would
# single out an existing account. The guards for it live with base_url in
# config/overrides/public_base_url.rb (ResetPasswordOrigin, EmailAuthOrigin,
# VerifyAccountOrigin): on these routes they answer with the same sent-response
# before any key write; direct and internal callers still raise. They are
# prepended, so VerifyAccountOrigin runs before this file's
# verify_account_email_resend rather than replacing it.
#
# HALT CONTRACT (why these overrides are safe)
# --------------------------------------------
# Each override neutralises its oracle by calling the route's sent-response
# method (reset_password_email_sent_response, email_auth_email_sent_response,
# verify_account_email_sent_response). Rodauth defines each with `response`,
# whose method runs require_response: the notice flash plus `redirect`, which
# in JSON mode is return_json_response -> request.halt, i.e. throw :halt. The
# overrides DEPEND on that halt: in account_from_login the halt is what stops
# the route from ever observing the nil account and emitting no_matching_login.
# If a future Rodauth changed these methods to return instead of halt, the
# overrides would fail OPEN (re-expose the oracle) rather than crash — so the
# enumeration regression specs
# (apps/web/auth/spec/integration/full/reset_password_request_enumeration_spec.rb,
# apps/web/auth/spec/integration/full_mfa/email_login_request_enumeration_spec.rb,
# apps/web/auth/spec/integration/full_mfa/verify_account_resend_enumeration_spec.rb)
# are the guard that must catch such a change. Pinned against Rodauth 2.45.0.
#
# RESIDUAL: TIMING SIDE-CHANNEL (accepted, not closed)
# ----------------------------------------------------
# Response content and status are now identical across every case, so the
# single-request CWE-204 oracle is closed. A LATENCY residual remains: the miss
# path halts right after the shared `accounts` SELECT, whereas a valid, eligible,
# non-throttled account additionally runs a few single-row statements on the
# route's key table (account_password_reset_keys, account_email_auth_keys or
# account_verification_keys, inside a transaction), generates a random key, and
# dispatches the email. Dispatch cost is deployment-dependent: an async AMQP
# publish (~ms) when background jobs are enabled, or a synchronous inline SMTP
# send (delivery.rb uses fallback: :sync, taken whenever RabbitMQ is absent — a
# common self-hosted config) that can dominate the delta. With jobs enabled the
# hit/miss gap sits near the network / Puma / GC jitter an off-host attacker
# sees (a noisy many-sample attack); under synchronous delivery the gap is
# larger and that statistical attack is easier. Either way it is not a
# single-request distinguisher — but not negligible.
#
# We deliberately DO NOT pad the miss path. The key tables are FK/PK-bound to
# accounts, so a non-existent login has no legal row to mirror; equalization
# would require junk accounts, insert-and-rollback theater, or dummy queue
# traffic — all new side effects and an abuse surface on an unauthenticated
# route — while a fixed sleep pad is defeated by variance analysis, taxes every
# legitimate request, and lets an unauthenticated caller pin Puma threads (a DoS
# amplifier); Ruby/Rack offers no constant-time guarantee across a DB + email
# chain regardless. Content-equalization above is the meaningful fix; the timing
# residual is accepted and documented. (Reviewed: Greptile P1 + 2nd review bot,
# issue #3857.)
#
# The residual is additionally BOUNDED by rate limiting on two of the routes:
# exploiting it statistically needs many samples per target, and
# config/hooks/reset_password_request.rb (#3872) and
# config/hooks/email_login_request.rb (RISK-2026-08-14-M04) throttle POST volume
# per client IP and per submitted login (Onetime::Security::
# ResetRequestRateLimiter, one scope per route) before the route — and
# therefore before account_from_login — runs. verify-account-resend has no such
# limiter; Rodauth's per-account resend window (verify_account_skip_resend_
# email_within) caps its emails, not its request volume.
#
# See also: config/rodauth_overrides.rb (verify_account error-flash overrides),
# config/overrides/duplicate_signup.rb (the same idea for create-account) and
# config/overrides/password_migration.rb (the `super` override idiom).
#
module Auth::Config::Overrides
  module LoginRequestEnumeration
    def self.configure(auth)
      auth_class = auth.instance_variable_get(:@auth)
      # Rodauth exposes the enabled feature symbols via the public `features`
      # reader on the auth class (Rodauth 2.45.0). Every sent-response and
      # predicate overridden here only exists when its feature is enabled; the
      # safe-navigation guard also makes this a no-op if `features` is ever
      # unavailable.
      features   = auth_class&.features || []
      enabled    = [:reset_password, :email_auth, :verify_account].select { |name| features.include?(name) }
      return if enabled.empty?

      configure_account_from_login(auth)
      configure_reset_password(auth) if enabled.include?(:reset_password)
      configure_email_auth(auth) if enabled.include?(:email_auth)
      configure_verify_account(auth) if enabled.include?(:verify_account)
    end

    # Oracle 1 on every route, and the "account exists but may not use this
    # route" oracle on the two routes that test eligibility inline (no
    # separate Rodauth method to override there).
    def self.configure_account_from_login(auth)
      # rubocop:disable-next Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        def account_from_login(login)
          account = super

          # Each sent-response below HALTS the request (see the HALT CONTRACT
          # note in the header), so the route's own
          # `account_from_login(...) && ...` check never sees the nil or the
          # ineligible account and never emits no_matching_login. Halting
          # here — before the key writes + email enqueue a valid account
          # performs — is the source of the accepted timing residual
          # documented in the header.
          case current_route
          when :reset_password_request
            # The unopen case on this route is Oracle 2 below
            # (reset_password_request_for_unverified_account), which the
            # route calls itself.
            if account.nil?
              Auth::Logging.log_auth_event(
                :reset_password_request_no_account,
                level: :info,
                email: login, # obscured by log_auth_event
              )
              reset_password_email_sent_response
            end
          when :email_auth_request
            # The route sends only to an open account
            # (`account_from_login(...) && open_account?`). A closed account
            # is never found (_account_from_login filters it), so it arrives
            # here as nil; an unverified one is found and is not open.
            if account.nil?
              Auth::Logging.log_auth_event(
                :email_auth_request_no_account,
                level: :info,
                email: login, # obscured by log_auth_event
              )
              email_auth_email_sent_response
            elsif !open_account?
              Auth::Logging.log_auth_event(
                :email_auth_request_unopen_account,
                level: :info,
                account_id: account_id,
              )
              email_auth_email_sent_response
            end
          when :verify_account_resend
            # The route resends only to an unverified account
            # (`account_from_login(...) && allow_resending_verify_account_email?`);
            # a verified account answering differently would say it exists.
            if account.nil?
              Auth::Logging.log_auth_event(
                :verify_account_resend_no_account,
                level: :info,
                email: login, # obscured by log_auth_event
              )
              verify_account_email_sent_response
            elsif !allow_resending_verify_account_email?
              Auth::Logging.log_auth_event(
                :verify_account_resend_ineligible_account,
                level: :info,
                account_id: account_id,
              )
              verify_account_email_sent_response
            end
          end

          # Fail-open return: on the routes above the halt normally fires and
          # we never reach here with a nil or ineligible account. If the halt
          # contract ever breaks, this bare `account` (nil on a miss) makes the
          # route re-expose the oracle rather than act on a non-account. A
          # guard clause would return the response object instead; an
          # explicit `return` trips Style/RedundantReturn.
          account
        end
      end
    end

    def self.configure_reset_password(auth)
      # rubocop:disable-next Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # ---- Reset Oracle 2: account exists but is not open --------------
        # Rodauth's default throws :unverified_account, revealing the account
        # exists. Return the same generic success instead. No reset email is
        # sent for a non-open account, mirroring the custom endpoint.
        def reset_password_request_for_unverified_account
          Auth::Logging.log_auth_event(
            :reset_password_request_unopen_account,
            level: :info,
            account_id: account_id,
          )
          reset_password_email_sent_response
        end

        # ---- Reset Oracle 3: email recently sent -------------------------
        # Rodauth's default renders the "reset_password_email_recently_sent"
        # error, which only an existing account can trigger. Keep the throttle
        # (do NOT resend), but return the same generic success so the throttled
        # case is indistinguishable from a fresh send or a non-existent login.
        def reset_password_email_recently_sent?
          return false unless super

          # Truthy super = a real account is throttled. HALTS with the generic
          # success (HALT CONTRACT). Intentionally no explicit boolean: on the
          # fail-open (halt-removed) path this returns the response value, which
          # the route treats as truthy and re-exposes the oracle. A defensive
          # `true` would change that documented fall-through return — omit it.
          reset_password_email_sent_response
        end
      end
    end

    def self.configure_email_auth(auth)
      # rubocop:disable-next Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # ---- Email-auth Oracle 3: email recently sent ---------------------
        # _email_auth_request answers a throttled account with the
        # "email_auth_email_recently_sent" error, which only an existing, open
        # account can trigger. Keep the throttle (no resend) and answer like a
        # fresh send. Scoped to the route: _email_auth_request is also reached
        # from the multi-phase login path (route :login) and from internal
        # requests (route nil), which keep stock behavior.
        def email_auth_email_recently_sent?
          recently_sent = super
          return recently_sent unless recently_sent && current_route == :email_auth_request

          # HALTS with the generic success (HALT CONTRACT); on the fail-open
          # path the response value is truthy and the stock error follows.
          email_auth_email_sent_response
        end
      end
    end

    def self.configure_verify_account(auth)
      # rubocop:disable-next Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # ---- Verify-resend Oracle 3: email recently sent ------------------
        # Same shape as the email-auth override above. Scoped to the route so
        # the internal request ResendVerifyAccount makes still raises for a
        # throttled account (that endpoint answers uniformly on its own).
        def verify_account_email_recently_sent?
          recently_sent = super
          return recently_sent unless recently_sent && current_route == :verify_account_resend

          verify_account_email_sent_response
        end

        # ---- Verify-resend Oracle 4: unverified account, no key row -------
        # verify_account_email_resend returns nil when the account has no
        # verification key (e.g. an unverified account created without one),
        # and the route then falls through to the no_matching_login error —
        # which, now that a missing login answers success, would single out
        # an existing account. Answer like a send; nothing is mailed.
        def verify_account_email_resend
          sent = super
          return sent if sent || current_route != :verify_account_resend

          Auth::Logging.log_auth_event(
            :verify_account_resend_no_key,
            level: :info,
            account_id: account_id,
          )
          verify_account_email_sent_response
        end
      end
    end

    private_class_method(
      :configure_account_from_login,
      :configure_reset_password,
      :configure_email_auth,
      :configure_verify_account,
    )
  end
end
