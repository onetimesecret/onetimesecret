.. A new scriv changelog fragment.

Fixed
-----

- Adding a recipient on a domain's incoming-secrets configuration no longer wipes existing recipients on save. The form now reads plaintext recipients from the ``IncomingConfig`` admin endpoint and writes the merged list back via ``PUT /api/domains/:extid/incoming-config``, replacing the legacy hashed-digest model that left the client unable to round-trip prior entries. (#3095)

Changed
-------

- Removed the legacy ``/api/domains/:extid/recipients`` endpoints (``GET`` / ``PUT`` / ``DELETE``) and their backing ``Onetime::CustomDomain::IncomingSecretsConfig`` JSON-blob model. ``CustomDomain::IncomingConfig`` is now the single source of truth for per-domain incoming recipients. The frontend service ``recipients.service.ts`` and the dual-state composable architecture in ``useIncomingConfig`` are likewise gone. (#3095)
- ``RecipientResolver#enabled?`` now returns ``false`` for any custom domain that has no ``IncomingConfig`` record. The implicit fallback to the legacy ``incoming_secrets`` jsonkey blob has been removed. (#3095)
- ``CustomDomain::IncomingConfig#public_recipients`` now returns the canonical ``{'digest' => ..., 'display_name' => ...}`` shape (string keys) used by the canonical-domain initializer and consumed by ``CreateIncomingSecret``. The earlier ``{hash:, name:}`` symbol-key shape has been retired. (#3095)

Deployment
----------

- Operators must run the ``migrate_incoming_secrets_to_config`` housekeeping chore as part of the deploy that picks up these changes, before traffic resumes. The chore copies entries from the legacy ``CustomDomain#incoming_secrets`` JSON blob into newly created ``IncomingConfig`` records and is idempotent::

      bin/ots housekeeping perform Onetime::CustomDomain migrate_incoming_secrets_to_config

  Until the chore has run, custom domains whose recipients were configured before this change will appear disabled to the resolver. The nightly housekeeping cron will run the chore as a safety net, but the explicit invocation at deploy time is the supported path. (#3095)

- The ``jsonkey :incoming_secrets`` field declaration on ``CustomDomain`` is intentionally retained for one release so the chore can re-read the legacy data if needed. It will be removed in a follow-up release once telemetry confirms all domains have a corresponding ``IncomingConfig`` record. (#3095)
