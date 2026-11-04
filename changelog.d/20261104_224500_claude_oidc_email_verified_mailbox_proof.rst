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
  Existing verified accounts stamped ``legacy`` (or with no stamp),
  ``autoverify`` or ``stripe_payment`` also change from ``true`` to
  ``false``. Such an account gets ``true`` once an operator verifies the
  address (``bin/ots customers verify`` or the colonel admin). Accounts
  created from an invitation also get ``false``: the invitation API returns
  the signup token to the inviter as well, so the signup does not prove that
  the invitee controls the mailbox. ``bin/ots customers verify`` keeps an
  ``invite_token`` stamp, so for those run ``bin/ots customers unverify`` and
  then ``verify``. The identity provider is off by default
  (``AUTH_OAUTH_ENABLED``). (#4735)

- The identity provider no longer takes claim values from the OpenID Connect
  ``claims`` request parameter. A requested ``value`` used to replace the
  value the server sends, and a requested ``values`` list could remove the
  claim, so the person signing in could set ``email_verified: true``, remove
  it, or choose their own ``name`` and ``preferred_username`` in the ID token
  and ``/userinfo``. Asking for a claim by name still works. (#4735)
