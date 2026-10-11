.. A new scriv changelog fragment.

Security
--------

- SSO-asserted email addresses are no longer treated as mailbox-verified.
  A new ``Customer#mailbox_verified?`` predicate (``verified_by`` one of
  ``email``, ``invite_token``, ``cli_provision``, ``colonel_admin``) now gates
  system roles, the last-colonel guard, impersonation, verification-secret
  display, the duplicate-signup resend and federated subscription claims.
  SSO JIT accounts defer the federated subscription claim until an operator
  verifies the address; ``bin/ots customers verify`` and the colonel admin
  can re-verify an already-verified account to record mailbox proof, which
  applies the deferred subscription. ``bin/ots customers doctor`` reports
  system-role holders without mailbox proof. Microsoft Entra's optional
  ``xms_edov: false`` claim now withholds the verified stamp
  (``domain_unverified``) and is refused by a tenant email-domain allowlist;
  ``xms_edov: true`` is domain-owner verification only, never mailbox proof.
  (#4735)

  **Upgrade note:** a colonel, admin or staff account whose ``verified_by`` is
  ``sso``, ``stripe_payment``, ``autoverify``, ``legacy`` or empty loses the
  role until it is verified with ``bin/ots customers verify EMAIL`` (or the
  colonel admin). Run ``bin/ots customers doctor`` before deploying to list
  affected accounts.
