.. A new scriv changelog fragment.

Added
-----

- Admin console can now list every organization that carries a Stripe customer
  id, via the new ``GET /api/colonel/billing/stripe-organizations`` endpoint and
  its CLI peer ``bin/ots billing orgs stripe``. The listing reads the existing
  ``organization:stripe_customer_id_index`` (HLEN for the count, HSCAN for the
  entries) and hydrates only the requested page, so it never scans every
  organization. Searching filters on the Stripe customer id server-side, and
  index entries whose organization no longer loads are reported as a per-page
  ``stale_count`` instead of rendering as broken rows.

- ``bin/ots domains create DOMAIN --org EXTID`` registers a custom domain
  against an organization from the shell. Create was the only colonel domain
  verb with no CLI peer; it now shares one implementation (and one audit event)
  with ``POST /api/colonel/domains``.

- ``bin/ots customers purge-one IDENTIFIER`` permanently deletes a single
  customer account and records it in the admin audit trail, matching
  ``DELETE /api/colonel/users/:user_id``. This is distinct from
  ``bin/ots customers purge``, which remains a bulk inactivity sweep.

- ``bin/ots billing catalog drift`` shows the same config-vs-live plan
  comparison as the admin console's billing catalog view, and exits non-zero
  when the two sides disagree so it can gate a deploy step.

- The colonel custom-domain listing accepts optional ``search``, ``status`` and
  ``org_id`` filters, applied before pagination.

Fixed
-----

- Colonel admin endpoints that document an "email or extid" identifier now
  actually accept an email address. The shared identifier sanitizer stripped
  ``@`` and ``.``, so ``user@example.com`` arrived at the lookup as
  ``userexamplecom`` and the request failed with "not found". This affected
  adding a member to an organization, changing or removing a membership, and
  the verify / unverify / purge / detail user endpoints.
