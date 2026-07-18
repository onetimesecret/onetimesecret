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
# Hook ownership (re-verify with:
#   rg -n --pcre2 "\bauth\.(before|after|around)_[a-z_0-9]+(?=\s+do\b)" apps/web/auth/config/):
#
#   account.rb          before_create_account, after_create_account,
#                       after_verify_account, after_reset_password_request,
#                       after_reset_password, after_change_password,
#                       after_close_account
#   login.rb            before_login_attempt, after_login, after_login_failure
#   logout.rb           before_logout, after_logout
#   mfa.rb              before_otp_setup_route, after_two_factor_authentication,
#                       after_otp_disable, after_otp_setup, before_otp_auth_route,
#                       before_otp_authentication, after_otp_authentication_failure,
#                       before_recovery_auth, after_add_recovery_codes,
#                       before_view_recovery_codes
#   email_auth.rb       before_email_auth_route, after_email_auth_request
#   webauthn.rb         after_webauthn_setup, before_webauthn_auth,
#                       after_webauthn_auth_failure, before_webauthn_remove
#   omniauth_tenant.rb  before_omniauth_callback_route (sole owner — logs
#                       callback start AND validates tenant context)
#   omniauth.rb         before_omniauth_create_account, after_omniauth_create_account
#
# Non-owners in this directory:
#   password.rb         intentionally EMPTY — password-lifecycle hooks live in
#                       account.rb (M-2 consolidation; see its module comment)
#   billing.rb          helper methods only (auth_class_eval), defines NO hooks
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
  require_relative 'hooks/login'
  require_relative 'hooks/logout'
  require_relative 'hooks/mfa'
  require_relative 'hooks/omniauth'
  require_relative 'hooks/omniauth_tenant'
  require_relative 'hooks/password'
  require_relative 'hooks/email_auth'
  require_relative 'hooks/webauthn'
end
