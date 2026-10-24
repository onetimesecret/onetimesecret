.. A new scriv changelog fragment.

Changed
-------

- ``bin/ots organizations`` is now the one command for organization records;
  ``bin/ots organization`` and ``bin/ots org`` are aliases for it, so every
  existing ``bin/ots org …`` invocation keeps working.
- The old option-verbs are subcommands: ``organizations list [--owner EMAIL]
  [--plan ID] [--limit N] [--verbose] [--json]`` and ``organizations show ORG
  [--json]``. ``--owner`` and ``--plan`` load organizations one by one until
  ``--limit`` match, so a filtered ``list`` is a dry run that reports the size
  of that walk unless ``--run`` is given. ``show`` takes an org extid, objid, Stripe customer id
  (``cus_…``), Stripe subscription id (``sub_…``) or custom-domain hostname in
  place of the ``--show``, ``--customer`` and ``--subscription`` flags, and so
  does every other ``organizations`` and ``memberships`` verb that takes an
  ORG.
- ``organizations --check`` is replaced by ``organizations doctor --all``,
  which now also reports an empty ``owner_id`` (check 1), a blank display name
  (check 7) and instances-index entries whose organization record is gone
  (repairable with ``--repair``).
- ``organizations add-member`` is folded into ``bin/ots memberships add ORG
  CUSTOMER [--role R] [--default]``. The new ``--default`` flag makes ORG the
  customer's default organization once they are a member of it.
  ``memberships add`` is now a dry run unless ``--apply`` is given (``--yes``
  is an alias), and no longer prompts.
- New ``bin/ots customers set-default-org CUSTOMER ORG`` sets the default
  organization of a customer who is already a member of ORG. It is a dry run
  unless ``--apply`` is given.
- ``organizations create``, ``delete``, ``transfer-ownership``, ``reconcile``
  and ``entitlement grant|revoke|clear``, and ``memberships remove``,
  ``set-role`` and ``entitlement grant|revoke|clear`` are now dry runs unless
  ``--apply`` is given, and no longer prompt. ``--yes``, ``-y`` and ``-f`` are
  aliases for ``--apply``, so scripts that pass ``--yes`` still write. A bare
  ``--json`` run now returns the dry-run result instead of refusing, and
  ``--apply`` with ``--dry-run`` is an error.
- Member listings (``organizations show``, ``organizations list --verbose``)
  show each member's public id (``ur…``), membership role and status, and an
  obscured email instead of internal ids. ``customers show`` prints the
  default organization and the organization list by extid.
- Customer arguments to ``bin/ots customers …``, ``memberships …`` and
  ``organizations …`` verbs also accept a customer objid. ``customers doctor``
  now accepts the same identifiers as the other customer verbs, and
  ``domains list --org-id`` / ``--org-extid`` each accept an extid or objid.
