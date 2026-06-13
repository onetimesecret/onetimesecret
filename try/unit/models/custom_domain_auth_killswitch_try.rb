# try/unit/models/custom_domain_auth_killswitch_try.rb
#
# frozen_string_literal: true

# Tests for the shared sign-in / sign-up availability resolvers that back both
# the display gate (ConfigSerializer) and the runtime gate (Core::Controllers::Base).
#
# The security property under test: the install-level (global) kill switch
# always wins. A per-domain SigninConfig/SignupConfig may only NARROW the
# global capability — it can never re-enable sign-in or sign-up when the
# operator has disabled it globally (AUTH_ENABLED / AUTH_SIGNIN / AUTH_SIGNUP).
#
# Run:
#   try try/unit/models/custom_domain_auth_killswitch_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

# Helper builders for in-memory configs (no persistence needed — the resolvers
# only read enabled?/signin_enabled?/signup_enabled?).
def signin_config(enabled:, signin_enabled:)
  Onetime::CustomDomain::SigninConfig.new(
    domain_id: 'ks_signin', enabled: enabled, signin_enabled: signin_enabled
  )
end

def signup_config(enabled:, signup_enabled:)
  Onetime::CustomDomain::SignupConfig.new(
    domain_id: 'ks_signup', enabled: enabled, signup_enabled: signup_enabled
  )
end

# --- SigninConfig.resolve_signin_enabled ---

## global on, no per-domain config => available
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(true, nil)
#=> true

## global off, no per-domain config => unavailable
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(false, nil)
#=> false

## nil global coerces to unavailable (defensive)
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(nil, nil)
#=> false

## global on, enabled config that allows sign-in => available
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(true, signin_config(enabled: true, signin_enabled: true))
#=> true

## global on, enabled config that disables sign-in => narrowed to unavailable
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(true, signin_config(enabled: true, signin_enabled: false))
#=> false

## KILL SWITCH: global off but enabled config tries to allow sign-in => still unavailable
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(false, signin_config(enabled: true, signin_enabled: true))
#=> false

## disabled config (master switch off) is ignored; global is authoritative
Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(true, signin_config(enabled: false, signin_enabled: false))
#=> true

# --- SignupConfig.resolve_signup_enabled ---

## global on, no per-domain config => available
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(true, nil)
#=> true

## global off, no per-domain config => unavailable
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(false, nil)
#=> false

## global on, enabled config that allows signup => available
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(true, signup_config(enabled: true, signup_enabled: true))
#=> true

## global on, enabled config that disables signup => narrowed to unavailable
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(true, signup_config(enabled: true, signup_enabled: false))
#=> false

## KILL SWITCH: global off but enabled config tries to allow signup => still unavailable
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(false, signup_config(enabled: true, signup_enabled: true))
#=> false

## disabled config (master switch off) is ignored; global is authoritative
Onetime::CustomDomain::SignupConfig.resolve_signup_enabled(true, signup_config(enabled: false, signup_enabled: false))
#=> true
