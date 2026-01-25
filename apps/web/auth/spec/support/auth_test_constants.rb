# apps/web/auth/spec/support/auth_test_constants.rb
#
# frozen_string_literal: true

# Test constants that mirror production values from apps/web/auth/config/features/*.rb
#
# These exist to avoid loading the full config chain which requires Onetime boot.
# Guideline: don't require any deeper than apps/web/auth/config.rb in specs,
# and even that triggers the boot chain - so use these constants instead.
#
# If production values change, update these to match.
#
# @see apps/web/auth/config/features/mfa.rb
module AuthTestConstants
  # MFA constants (from config/features/mfa.rb)
  MFA_RECOVERY_CODES_LIMIT = 4
  MFA_OTP_AUTH_FAILURES_LIMIT = 7

  # Account status IDs (from migration seed data)
  STATUS_UNVERIFIED = 1
  STATUS_VERIFIED = 2
  STATUS_CLOSED = 3
end
