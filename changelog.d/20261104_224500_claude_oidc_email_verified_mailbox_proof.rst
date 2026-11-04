.. A new scriv changelog fragment.

Security
--------

- The OAuth 2.0 / OpenID Connect identity provider asserts
  ``email_verified: true``, in ID tokens and from ``/userinfo``, only for an
  account with mailbox proof: its authentication account is Verified and its
  customer record was verified by email, the CLI or the colonel admin. Every
  other account gets ``email_verified: false``. Relying parties now see
  ``false`` for accounts created through SSO, which open Verified because the
  upstream identity provider vouched for the address, not because anyone
  proved the mailbox, and for accounts whose customer record cannot be read.
  An SSO account gets ``true`` once an operator verifies the address
  (``bin/ots customers verify`` or the colonel admin). Accounts created from
  an invitation also get ``false``: the invitation API returns the signup
  token to the inviter as well, so the signup does not prove that the invitee
  controls the mailbox. The identity provider is off by default
  (``AUTH_OAUTH_ENABLED``). (#4735)
