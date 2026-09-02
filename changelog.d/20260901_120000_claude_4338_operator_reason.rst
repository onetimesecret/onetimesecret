.. A new scriv changelog fragment.

Added
-----

- Destructive operator actions now accept an optional **reason** that is
  recorded alongside them in the admin audit trail (#4338). The trail already
  said who did what to whom and how it went; it never said *why*, so "purged
  this account" could not be told apart from a GDPR erasure, a mistake, or an
  insider clearing their tracks without leaving the system to find the ticket.

- Three surfaces send it: the admin console's confirmation dialog grows an
  optional reason box on purge, role change, unsuspend, session revoke and
  revoke-all, secret delete, custom-domain removal and organization delete;
  the matching colonel API endpoints accept a ``reason`` parameter (in the body
  for POST, on the query string for DELETE); and the CLI peers take
  ``--reason`` (``customers purge-one`` / ``role promote`` / ``role demote`` /
  ``unsuspend``, ``org delete``, ``memberships remove`` / ``set-role``,
  ``session delete``, ``domains remove``, ``queue dlq purge`` — joining
  ``customers suspend``, which already had one).

- The reason also rides the *attempted* actions: a no-change attempt (setting a
  role an account already holds) and a dry-run preview each carry it, because
  each has a why worth reading.

Changed
-------

- Nothing is required yet. This is the first half of a two-step rollout: every
  surface can send a reason, and nothing rejects a request that omits one, so
  no operator is blocked mid-incident while the surfaces catch up. An action
  taken without a reason records exactly what it recorded before — a blank or
  whitespace-only reason is treated as no reason at all, never as an empty one.

- Reasons are stored as free operator text, bounded at 255 characters (one
  under the audit store's per-value limit, so what is typed is what a reviewer
  reads back) with markup stripped. They are visible to anyone who can read the
  audit log or its CSV/NDJSON export, so write them for that audience.
