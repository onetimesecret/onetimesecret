.. A new scriv changelog fragment.

Changed
-------

- ``bin/ots organizations`` is now the one command for organization records;
  ``bin/ots organization`` and ``bin/ots org`` are aliases for it, so every
  existing ``bin/ots org …`` invocation keeps working.
- The old option-verbs are subcommands: ``organizations list [--owner EMAIL]
  [--plan ID] [--limit N] [--verbose] [--json]`` and ``organizations show ORG
  [--json]``. ``show`` takes an org extid, objid, Stripe customer id
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
  customer's default organization once they are a member of it; the
  confirmation prompt (skipped with ``--yes``) takes the place of
  ``--dry-run``.
- Member listings (``organizations show``, ``organizations list --verbose``)
  show each member's public id (``ur…``), membership role and status, and an
  obscured email instead of internal ids. ``customers show`` prints the
  default organization and the organization list by extid.
- Customer arguments to ``bin/ots customers …``, ``memberships …`` and
  ``organizations …`` verbs also accept a customer objid. ``customers doctor``
  now accepts the same identifiers as the other customer verbs, and
  ``domains list --org-id`` / ``--org-extid`` each accept an extid or objid.
