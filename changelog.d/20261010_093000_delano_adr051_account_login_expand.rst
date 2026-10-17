.. A new scriv changelog fragment.

Added
-----

- Auth database migration 012 adds an internal ``login`` column and three
  contact-email verification columns (``email_verified_at``,
  ``email_verified_by``, ``email_verification_hold``) to ``accounts``. All
  four are nullable and unused by this release; sign-in, account creation and
  the email login column are unchanged. The new
  ``bin/ots customers backfill-logins`` command (dry run by default) fills
  them from the existing account–Customer link, and ``bin/ots customers
  doctor`` reports rows that still lack a login or whose login disagrees with
  their Customer. This is the first, expand-only step of the account-model
  change in ADR-051 (SSO email-less accounts); later steps are gated on the
  backfill having completed. Rolling back to a release without migration
  012 is safe at this step.
