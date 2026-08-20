.. A new scriv changelog fragment.

Added
-----

- Organizations can now be deleted by an operator. ``bin/ots org delete ORG``
  and ``DELETE /api/colonel/organizations/:org_id`` (surfaced in the admin
  console's Caution Zone on the organization detail page) both run the same
  shared ``Onetime::Operations::Org::Delete`` operation the customer-facing
  ``DELETE /api/organizations/:extid`` now uses. Previously the only operator
  option was a hand-run ``bin/console`` recipe, which skipped three things the
  API path did: it left the org in ``Organization.instances`` (a dangling entry
  that ``bin/ots org doctor --all``, membership counting and the org list all
  walk), it never emailed the former members, and it left ``default_org_id``
  pointing at a deleted org until someone ran
  ``bin/ots customers doctor --repair``.

- The delete previews by default on every surface. The CLI prints the plan —
  display name, plan, members and their addresses, pending invitations,
  domains, and the ``default_org_id`` rows it will repair — before asking to
  confirm; the console fetches the same plan and requires the organization id
  to be retyped. Guardrails refuse a delete that would leave the datastore or
  the account worse off: attached custom domains, a default (personal)
  workspace, an active subscription, or the owner's only organization. The two
  middle guards can be overridden per-guard from the operator surfaces only
  (``--force-default`` / ``--force-subscription``); nothing here ever cancels a
  Stripe subscription.

Security
--------

- ``DELETE /api/organizations/:extid`` now refuses to delete a customer's
  default workspace. That rule existed in ``Organization#can_delete?`` — which
  has never had a caller — and in a Vue ``v-if``, so a request made directly
  against the API deleted the owner's default workspace and bypassed the
  "contact us" flow the UI promises. The server now enforces it. (Scope: an
  owner destroying their own organization, not a cross-tenant escape.)

Changed
-------

- Deleting an organization whose subscription can still bill is now refused on
  the customer-facing endpoint. That covers ``active`` and ``trialing`` and
  also the delinquent states — ``past_due`` and ``unpaid`` — where
  Stripe is still retrying or can resume. Nothing in the delete path talks to
  Stripe, so the subscription has to be cancelled first — otherwise it keeps
  billing against a record that no longer exists. An abandoned checkout
  (``incomplete``) does not block the delete; Stripe expires it on its own.

- The workspace Caution Zone pre-disables its delete button for an organization
  whose subscription can still bill, alongside the existing custom-domain case,
  and says which one is blocking. Organizations now carry an
  ``active_subscription`` flag in their API payload for it — read from the
  stored subscription status, no Stripe call. The server refuses either case
  regardless; a payload without the flag leaves the button live rather than
  locking an owner out.

AI Assistance
-------------

- Claude extracted the teardown out of the ``DeleteOrganization`` logic class
  into the shared operation, wrote the CLI and colonel adapters and the admin
  console's delete flow, and added the operation, adapter and console
  coverage.
