# apps/web/auth/config/hooks.rb
#
# frozen_string_literal: true

#
# INVARIANT: Rodauth hooks do NOT chain.
#
# Each `auth.<hook> do ... end` call REPLACES the previous definition for that
# hook name — hooks are methods, and the last definition wins. The registration
# order in config.rb (the Hooks::*.configure calls) is therefore a PRECEDENCE
# list, not a pipeline: if two modules define the same hook, the one registered
# LAST silently clobbers the other. That is exactly what happened in bug #3275
# (see hooks/password.rb for the canonical write-up, and the before_create_account
# NOTE in hooks/account.rb).
#
# Rule: every hook name has exactly ONE owning module. To add behavior to an
# existing hook, edit the owning file — never redefine the hook elsewhere.
# Cross-cutting logic (e.g. billing) is exposed as helper methods via
# auth_class_eval and called conditionally from the owning hook (see billing.rb).
# The duplicate-hook guard spec enforces this one-owner invariant.
#
# WRAPPERS are the one sanctioned way to run code around a hook from another
# file, and they are a different mechanism with the opposite property: a module
# that defines the hook method with `def`, calls `super`, and is prepended onto
# the auth class DOES chain, in ancestor order. The registration rule above
# cannot see one, and an unplanned second wrapper is as dangerous as a second
# registration: a missing or reordered `super` can skip tenant validation,
# consume the Connect intent twice, or move Connect authorization behind a gem
# shortcut. So wrappers are owned too (#4432):
#
#   - the approved set is closed. Today it is exactly one module,
#     Auth::Config::Hooks::OmniAuthConnect::Callback, around
#     before_omniauth_callback_route, prepended once from hooks/omniauth.rb;
#   - its position is fixed: prepended, so it runs FIRST, and its `super`
#     reaches the gem's hook method, which calls the block registered by
#     omniauth_tenant.rb. Nothing application-owned sits between them.
#
# Enforced in two places, because neither sees everything.
#
#   - Static: apps/web/auth/spec/config/hook_ownership_spec.rb fails on any
#     `def before_*/after_*/around_*` under config/ that is not in its approved
#     list, and on an approved module prepended zero or several times.
#   - Runtime: apps/web/auth/spec/integration/full/omniauth_callback_wrapper_order_spec.rb
#     reads the configured class's ancestors, so it also catches a wrapper
#     defined outside config/ or built with define_method, and it is what
#     asserts the order.
#
# Adding a wrapper means changing both specs and this section in the same
# commit, with the reason it cannot live in the owning hook.
#
# Hook ownership (re-verify with:
#   rg -n --pcre2 "\bauth\.(before|after|around)_[a-z_0-9]+(?=\s+do\b)" apps/web/auth/config/):
#
#   account.rb          before_create_account, after_create_account,
#                       after_verify_account, after_reset_password_request,
#                       after_reset_password, after_change_password,
#                       after_close_account
#   login.rb            before_login_attempt, after_login, after_login_failure
#   logout.rb           before_logout, after_logout
#   mfa.rb              before_otp_setup_route, after_otp_disable,
#                       after_otp_setup, before_otp_auth_route,
#                       before_otp_authentication, after_otp_authentication_failure,
#                       before_recovery_auth, after_add_recovery_codes,
#                       before_view_recovery_codes
#   two_factor.rb       after_two_factor_authentication (completion of ANY
#                       second factor — OTP, recovery code, or WebAuthn
#                       passkey; registered when mfa OR webauthn is enabled,
#                       NOT only mfa — see the ownership note in that file)
#   email_auth.rb       before_email_auth_route, after_email_auth_request
#   email_auth_request.rb  before_email_auth_request_route (rate limiting per
#                       client IP, audit 2026-08-02 L-5; NOT the redemption-
#                       side hooks, which email_auth.rb owns)
#   reset_password_request.rb  before_reset_password_request_route (rate
#                       limiting per client IP + per submitted login, #3872)
#   restrict_to.rb      before_rodauth (restrict_to enforcement — 404s a sign-in
#                       method the request host restricts away; fires for
#                       EVERY route, so it is the one hook that must stay cheap
#                       and must never be redefined elsewhere; see
#                       ADR-034#restrict-to-is-an-access-control-not-a-display-preference
#                       / #reject-as-not-found-not-forbidden),
#                       before_email_auth_request (the multi-phase-login magic
#                       link, which is not its own route)
#   create_account.rb   before_create_account_route (rate limiting per client
#                       IP, #3948; NOT before_create_account, which account.rb
#                       owns and which fires later in the submission)
#   webauthn.rb         after_webauthn_setup, before_webauthn_auth,
#                       after_webauthn_auth_failure, before_webauthn_remove,
#                       after_webauthn_remove
#   omniauth_tenant.rb  before_omniauth_callback_route (sole owner — logs
#                       callback start AND validates tenant context)
#   omniauth.rb         before_omniauth_create_account, after_omniauth_create_account
#
# Non-owners in this directory:
#   password.rb         intentionally EMPTY — password-lifecycle hooks live in
#                       account.rb (M-2 consolidation; see its module comment)
#   billing.rb          helper methods only (auth_class_eval), defines NO hooks
#   oauth.rb            registers get_oidc_param (a keyed value method, not a
#                       before/after hook); its only_json? exemption is owned
#                       by config/json_mode.rb (#3104)
#   omniauth_connect.rb registers NO hook. It holds the one approved WRAPPER
#                       (see WRAPPERS above) around before_omniauth_callback_route,
#                       installed by omniauth.rb: auth_class_eval { prepend ... }.
#                       The hook is still OWNED by omniauth_tenant.rb; this file
#                       chains Connect authorization ahead of the tenant validation.
#
# Method overrides (a different mechanism — they replace Rodauth methods, not
# register hooks) live in config/overrides/: error_handling.rb defines the
# around_rodauth wrapper, password_migration.rb overrides password_match?.
# See config/overrides.rb.
#
# Log levels:
#   OT.li - Normal operations, attempts, successes
#   OT.le - Security events, failures, lockouts
#
# Logs authentication events for debugging and security monitoring.
# Emails obscured. No passwords, tokens, or keys logged.

module Auth::Config::Hooks
  require_relative 'hooks/account'
  require_relative 'hooks/billing'
  require_relative 'hooks/create_account'
  require_relative 'hooks/login'
  require_relative 'hooks/logout'
  require_relative 'hooks/mfa'
  require_relative 'hooks/oauth'
  require_relative 'hooks/omniauth'
  require_relative 'hooks/omniauth_tenant'
  require_relative 'hooks/password'
  require_relative 'hooks/reset_password_request'
  require_relative 'hooks/restrict_to'
  require_relative 'hooks/email_auth'
  require_relative 'hooks/email_auth_request'
  require_relative 'hooks/two_factor'
  require_relative 'hooks/webauthn'
end
