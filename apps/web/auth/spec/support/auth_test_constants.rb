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

  # Default TOTP issuer — matches BrandSettingsConstants::GLOBAL_DEFAULTS[:totp_issuer].
  # Production resolves dynamically from brand config; tests use the static default.
  MFA_OTP_ISSUER = 'OTS'

  # Account status IDs (from migration seed data)
  STATUS_UNVERIFIED = 1
  STATUS_VERIFIED = 2
  STATUS_CLOSED = 3

  # Shared password for integration specs that seed an Argon2 hash and then log
  # in through the real Rack stack. Defined here (not per-file) so two specs
  # loaded in one RSpec process don't warn on constant redefinition.
  TEST_PASSWORD = 'TestPassword123!'

  # Tables whose rows must survive per-example cleanup (clear_auth_database):
  #   - schema_info / schema_migrations: Sequel's migration bookkeeping
  #   - account_statuses: seed-once reference table backing accounts.status_id;
  #     deleting its rows orphans the FK and breaks the next create_account
  #   - oauth_applications: the dev SP client (SeedDevOAuthClient) is seeded
  #     once per file in before(:all); wiping it per example leaves every
  #     subsequent oauth_grants insert with a NULL oauth_application_id
  # Add any future seed-once reference table here.
  #
  # CAVEAT (PostgreSQL): exclusion here is not a guarantee. The PG branch of
  # clear_auth_database uses TRUNCATE ... CASCADE, which also truncates any
  # table holding an FK to a truncated table — oauth_applications.account_id
  # references accounts (migration 009), so its rows do NOT survive on PG.
  # SQLite (per-table DELETE) honours the exclusion literally. Specs must
  # therefore re-seed such rows per example, not in before(:all); see
  # spec_helper.rb#ensure_dev_oauth_client!.
  PRESERVED_TABLES = %i[schema_info schema_migrations account_statuses oauth_applications].freeze
end
