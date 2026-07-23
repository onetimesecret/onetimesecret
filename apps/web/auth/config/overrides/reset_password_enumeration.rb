# apps/web/auth/config/overrides/reset_password_enumeration.rb
#
# frozen_string_literal: true

#
# Reset-Password-Request Enumeration Safety (issue #3857)
#
# MECHANISM: method overrides via `auth_class_eval` — these REPLACE Rodauth
# methods (overrides clobber like hooks do: last definition wins), which is why
# this file lives in config/overrides/ rather than config/hooks/. `super` inside
# each override invokes the stock Rodauth implementation (features are included
# as modules, so the originals live in the class's ancestry).
#
# WHY THIS EXISTS
# ---------------
# The Rodauth `:reset_password` feature is enabled (config/features/
# account_management.rb). In `full` auth mode the Rodauth app is mounted at
# `/auth` and — because Rack::URLMap dispatches to the longest matching prefix —
# handles EVERY `/auth/*` route, including `POST /auth/reset-password-request`.
# That route is therefore the one actually exposed to unauthenticated callers;
# it shadows the enumeration-safe custom endpoint in apps/web/core (mounted at
# `/`).
#
# Stock Rodauth 2.44.0 (lib/rodauth/features/reset_password.rb, the
# reset_password_request route) distinguishes "account exists" from "no account"
# on that request path in THREE ways, each an account-existence oracle (CWE-204):
#
#   1. no matching login         -> throw_error_reason(:no_matching_login, ...)
#   2. account not open/verified -> reset_password_request_for_unverified_account
#                                   (throws :unverified_account)
#   3. email recently sent       -> "reset_password_email_recently_sent" error
#
# A registered, verified account returns 200 { success: "An email has been
# sent..." }, whereas a non-existent login returns an error tuple carrying a
# `field-error`. Comparing the two lets an unauthenticated caller enumerate
# accounts — exactly the posture the custom endpoint
# (apps/api/account/logic/authentication/reset_password_request.rb) was written
# to prevent.
#
# WHY OVERRIDE RATHER THAN DISABLE THE ROUTE
# ------------------------------------------
# We cannot simply disable the request route. In full mode the reset *consume*
# path (`/auth/reset-password`) is Rodauth's and expects a Rodauth-generated
# reset token, and the reset email links to Rodauth's reset URL
# (config/email/reset_password.rb) — so the request path must remain Rodauth's to
# mint that token. Instead we neutralise the three oracle branches so every POST
# yields the SAME generic "email sent" response, regardless of whether the login
# maps to an account, whether that account is open, and whether an email was
# recently sent.
#
# Side effects (reset-key creation + email) still happen only for a valid, open,
# non-throttled account, and Rodauth's resend throttle is PRESERVED: a
# recently-emailed account returns the same generic success WITHOUT resending, so
# closing the oracle does not open an email-bombing regression.
#
# See also: config/rodauth_overrides.rb (verify_account error-flash overrides)
# and config/overrides/password_migration.rb (the `super` override idiom).
#
module Auth::Config::Overrides
  module ResetPasswordEnumeration
    def self.configure(auth)
      auth_class = auth.instance_variable_get(:@auth)
      # reset_password_email_sent_response and the two reset-request predicates
      # only exist when the feature is enabled; nothing to harden otherwise.
      return unless auth_class&.features&.include?(:reset_password)

      # rubocop:disable Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # ---- Oracle 1: no matching login ----------------------------------
        # account_from_login is SHARED with the login route, so the
        # enumeration-safe short-circuit is scoped to the reset-password-request
        # route via current_route (set by Rodauth's route wrapper). On every
        # other route — login above all — a missing account behaves exactly as
        # before. Internal requests bypass the wrapper, leaving current_route
        # nil, so they are unaffected too.
        def account_from_login(login)
          account = super

          if account.nil? && current_route == :reset_password_request
            Auth::Logging.log_auth_event(
              :reset_password_request_no_account,
              level: :info,
              email: login, # obscured by log_auth_event
            )
            # Respond exactly as the success path would; halts the request, so
            # the `unless account_from_login(...)` check in the route never sees
            # the nil and never emits no_matching_login.
            reset_password_email_sent_response
          end

          account
        end

        # ---- Oracle 2: account exists but is not open (unverified/closed) --
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

        # ---- Oracle 3: email recently sent --------------------------------
        # Rodauth's default renders the "reset_password_email_recently_sent"
        # error, which only an existing account can trigger. Keep the throttle
        # (do NOT resend), but return the same generic success so the throttled
        # case is indistinguishable from a fresh send or a non-existent login.
        def reset_password_email_recently_sent?
          return false unless super

          reset_password_email_sent_response
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition
    end
  end
end
