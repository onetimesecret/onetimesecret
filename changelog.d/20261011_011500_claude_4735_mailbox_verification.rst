.. A new scriv changelog fragment.

Security
--------

- SSO-asserted email addresses are no longer treated as mailbox-verified.
  A new ``Customer#mailbox_verified?`` predicate (``verified_by`` one of
  ``email``, ``invite_token``, ``cli_provision``, ``colonel_admin``) now gates
  system roles, the last-colonel guard, impersonation, verification-secret
  display, the simple-mode duplicate-signup resend and the deferred federated
  subscription claim (a standard signup with email verification enabled, and
  every SSO JIT account). The deferral is a property of the customer record,
  not of the code path that creates the workspace: an unverified account on
  a deployment with email verification enabled, like an SSO JIT account
  without mailbox proof, is deferred on every path, so a workspace repair
  by ``bin/ots customers doctor --repair``, a lazy workspace creation or the
  billing self-heal cannot claim a pending subscription that signup
  deferred. The rule fails closed in a process that has not exported
  ``AUTHENTICATION_MODE`` (a host shell, or a container started with a plain
  ``docker run`` and no ``-e AUTHENTICATION_MODE``): such a process resolves simple auth mode by
  default and now defers the claim, with a warning, rather than read the
  verification step as absent, so a ``bin/ots billing webhooks replay`` from
  that shell or a billing worker started without the variable stores the
  subscription as pending instead of applying it;
  ``bin/ots customers doctor --repair`` refuses in that state, as the
  destructive customer commands do (the audit runs in any mode), and the
  full-stack compose file now exports the variable on the ``worker-email``
  and ``scheduler`` services as it did on ``app``. In simple auth mode the
  emailed verification link, once followed, now also applies a federated
  subscription that was deferred this way, through the same verification
  operation every other mailbox-proof stamp uses. The link applies only a
  subscription for the account's own address, and only when it was sent to
  that address, since it proves only the mailbox it was sent to: a workspace
  whose billing email names another address keeps the pending record, and so
  does an account whose address an operator changed after the link was sent
  (``bin/ots customers change-email`` without ``--keep-verified``). Such a
  link, like one sent before this release, verifies the account as before
  and applies nothing. A verification link minted
  in simple auth mode and followed after a switch to full auth mode no
  longer records verification. An account whose Rodauth row is still
  Unverified verifies through the normal email verification instead; one
  that Rodauth already counts as verified, without mailbox proof in its
  record, needs ``bin/ots customers verify``. A deployment that has
  disabled email verification, with its auth mode settled, still claims at
  standard signup without mailbox proof, as before, with the existing
  security-audit log line. SSO JIT accounts defer the claim until an
  operator verifies the address; ``bin/ots customers verify`` and the colonel
  admin can re-verify an already-verified account to record mailbox proof,
  which applies the deferred subscription, and re-running either on an
  already mailbox-verified account retries a claim that failed without
  changing the stored mailbox-proof provenance (an ``email`` stamp is not
  rewritten to ``cli_provision`` or ``colonel_admin``).
  ``bin/ots customers doctor`` reports every system-role holder (colonel,
  admin, staff) without mailbox proof. Microsoft Entra's optional
  ``xms_edov: false`` claim now withholds the verified stamp
  (``domain_unverified``) and is refused by a tenant email-domain allowlist;
  ``xms_edov: true`` is domain-owner verification only, never mailbox proof.
  Verification secrets now identify themselves (``account_verification``,
  ``password_reset``, ``email_change``); an email-change confirmation link
  minted before the upgrade is recognised by how it was minted and never
  stamps the current address, even after a second request superseded it.
  ``customers unverify`` no longer verifies an unverified colonel-role account
  through the last-colonel rollback; ``customers create --no-verified`` writes
  no provenance. An operator verification in full auth mode reconciles the
  Rodauth row on every change, and a deferred federated subscription is never
  applied to a workspace that already owns a local subscription. The shared
  password-recovery pointer is now replaced and cleared with a server-side
  compare-and-set, so a recovery link requested while a verification resend
  or a welcome-link reveal is in flight still redeems. A federated workspace
  records when its subscription state was last applied in full
  (``subscription_synced_at``) and its place in a sync order shared with
  pending records (``subscription_sync_version``); a verification retry
  discards a pending federated record that predates it instead of replaying
  it over a later cancellation, applies one stored after it even within the
  same second, and re-applies a record whose first claim failed before the
  entitlements were written. The claim and the federated subscription
  webhooks take one lock per email hash and the claim reads the workspace
  and the pending record inside it, so a cancellation that arrives during a
  claim is applied after it instead of being overwritten. A federated
  subscription webhook no longer applies a plan to a workspace whose owner
  lacks mailbox proof and is either SSO-provisioned or still unverified on a
  deployment with email verification enabled; it updates the pending record
  for the claim that follows verification. A workspace that already has an
  active federated plan keeps receiving updates, and cancellations and
  pauses still apply to every workspace; a pause that reaches a workspace
  whose owner has mailbox proof records the sync order and retires a pending
  record stored before it, so a later verification retry cannot restore an
  active plan over the pause. (#4735)

  **Upgrade note:** a colonel, admin or staff account whose ``verified_by`` is
  ``sso``, ``stripe_payment``, ``autoverify``, ``legacy`` or empty loses the
  role until it is verified with ``bin/ots customers verify EMAIL`` (or the
  colonel admin). Run ``bin/ots customers doctor`` before deploying to list
  affected accounts.
