.. A new scriv changelog fragment.

Added
-----

- Auth database migration 015 adds an internal ``login`` column and three
  contact-email verification columns (``email_verified_at``,
  ``email_verified_by``, ``email_verification_hold``) to ``accounts``. All
  four are nullable and unused by this release; sign-in, account creation and
  the email login column are unchanged. The new
  ``bin/ots customers backfill-logins`` command (dry run by default) fills
  them from the existing account–Customer link, and every verification change
  after it writes the verification columns as well; both record mailbox proof only
  (a Customer verified with a provenance in
  ``Onetime::Customer::MAILBOX_VERIFIED_BY`` under the row's own address) and
  leave an IdP-, payment- or legacy-verified account unverified in SQL, where
  the Customer record keeps its own answer. A row a verification change has
  already written keeps those columns, and their time, through the backfill.
  The backfill never links a closed account
  row, or an address that case folding would rewrite (``ß`` to ``ss``), to a
  Customer by address, nor a row to a Customer that a stale email-index entry
  names under another address (``customers doctor --all --repair`` fixes the
  index). An operator email change and the doctor's drift repair clear the
  three verification columns when the mailbox changes. A confirmed
  self-service email change records the followed link as mailbox proof for
  the new address in both stores (``verified_by`` ``email``), for an account
  that was already verified: one verified by an IdP, a payment, autoverify or
  a legacy stamp gains mailbox proof, which system roles and the deferred
  federated subscription claim require. ``bin/ots customers doctor`` reports rows that still lack a login, whose login disagrees with their
  Customer, or whose SQL verification disagrees with the Customer's mailbox
  proof. This is the first, expand-only step of the account-model
  change in ADR-051 (SSO email-less accounts); later steps are gated on the
  backfill having completed. A release without migration 015 refuses to
  start in full mode against a database that has applied it, so rolling
  back past this release needs the auth schema migrated down first, with
  this release's migration files. The down migration drops only the four
  new columns and the login index. (#4744)
