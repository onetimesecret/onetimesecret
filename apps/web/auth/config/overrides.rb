# apps/web/auth/config/overrides.rb
#
# frozen_string_literal: true

#
# Method OVERRIDES — distinct mechanism from config/hooks/.
#
# Files here replace Rodauth methods (`auth.password_match?`,
# `auth.around_rodauth`) rather than registering before/after hooks. The
# clobber semantics are the same as hooks (last definition of a method name
# wins; see config/hooks.rb for the invariant and #3275 history), but the
# mechanism is a method override: Rodauth calls these methods directly, and
# `super` inside them invokes the stock implementation.
#
# See also: config/rodauth_overrides.rb (verify_account error-flash
# overrides, kept at its original path to avoid churn).
#
module Auth::Config::Overrides
  require_relative 'overrides/error_handling'
  require_relative 'overrides/password_migration'
end
