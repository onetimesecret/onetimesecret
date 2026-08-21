.. A new scriv changelog fragment.

Fixed
-----

- A schema-validation failure discarded the one thing needed to diagnose it.
  The Colonel organization-detail bug that opened this branch was found by
  hand because the event said only that validation failed; it now reports
  ``record.subscription_period_end``, ``invalid_type``, expected ``string``,
  received ``number`` — field path, issue code, and the *types* on both sides,
  with no value from the payload.

- Frontend events now carry ``dist: 'frontend'``. Sentry resolves an artifact
  bundle only when release *and* dist both match, and events carried
  ``dist: null`` while the CI upload tagged ``--dist=frontend``, so no frame
  could ever have symbolicated. This is the frontend half; CI's half, and the
  reason the upload also shipped zero files, are fixed separately in
  ``fix/sentry-sourcemap-delivery``. Both are required before a frame
  symbolicates, in either merge order.

Added
-----

- A privacy-preserving telemetry boundary for the frontend Sentry client, with
  five parts, each enforced structurally rather than by convention:

  - **Value-free schema diagnostics.** ``ZodError`` rendering goes through one
    projection that emits only schema/context name, field path, issue code,
    expected and received *type*, issue count, and the parameterized API
    route. Zod's own issue text, ``issue.input``, ``unrecognized_keys`` key
    names (payload-derived) and ``issue.params`` are all refused — a real
    audit found a ``params`` carrying a live Stripe secret key. Rows are flat
    by contract because Sentry's ``normalizeDepth`` silently collapses a
    nested row to the string ``[Object]``.

  - **Pseudonymous actor references.** ``Onetime::Utils::TelemetryRef``
    derives an opaque, keyed, one-way ``user.id`` so the same person maps to
    the same identity across events without an email, customer id, extid or IP
    reaching the backend. It is deliberately *not* the federation email hash,
    which is simultaneously a queryable datastore index and a field in Stripe
    customer metadata.

  - **Parameterized route tags.** The endpoint behind a failure is reported as
    ``/api/colonel/organizations/:org_id``; the resolved form is never
    retained, even in memory.

  - **Pseudonymous resource references.** Because the route above is
    parameterized, every organization's failure lands on one aggregate and
    "one organization is broken" reads identically to "every organization is
    broken" — the first question the Colonel bug raised. The organization
    detail response now carries ``organization_ref``, an opaque, keyed,
    one-way 16-hex value from the same ``TelemetryRef`` derivation, and a
    failing parse attaches it as a Sentry *tag*. It answers that question by
    cardinality alone. The value is recovered from the raw payload, since a
    failed parse leaves no parsed record, and is shape-checked before it is
    emitted; it is sent only for schemas explicitly enrolled in an
    exact-match ``(schema, path)`` allowlist — today just the internal Colonel
    organization detail response — and an unenrolled schema emits nothing. The
    organization's extid, display name, contact/owner/billing addresses and
    Stripe identifiers are not sent, and the per-session bootstrap telemetry
    block is unchanged: the reference rides the resource it describes.

  - **Metadata-only breadcrumbs.** Per-category key allowlists, so keys that
    do not exist yet are refused by default. HTTP breadcrumbs keep URL,
    method, status, timing, byte counts and correlation ids; bodies, headers
    and console argument lists are dropped. Every allowlisted key also
    declares a primitive type, so a producer writing a payload where a byte
    count belongs has it dropped rather than shipped.

Security
--------

- Telemetry references — actor and organization alike — are scoped to one
  data-residency jurisdiction, not one federation. Regional instances share ``FEDERATION_SECRET`` by design and
  report into one telemetry backend, so a region-independent reference would
  emit the identical ``user.id`` from the EU and US instances — a ready-made
  join key proving one data subject is present in both, which is exactly the
  inference the residency architecture exists to prevent. The residency scope
  is mixed into the derivation unconditionally, with no opt-out.

- An undeclared residency *withdraws* the shared key rather than widening the
  reference: ``FEDERATION_SECRET`` is refused and the derivation falls back to
  the per-deployment ``ACCOUNT_ID_SECRET``. The safe state is the one an
  operator gets for free, and the emitted ``actor_scope`` label narrows with
  it, so an event never claims a reference is comparable further than it is.

- Free text reaching the telemetry surface is scrubbed by shape — emails,
  verifiable identifiers, Onetime external ids, prefixed credentials and
  object ids, UUIDs, and IP addresses — with each net emitting its own
  sentinel so a reader knows *what* was removed. The nets are deliberately
  narrow at the edges that matter for diagnosis: trace ids, commit hashes,
  version strings, Ruby constant paths and schema field names survive intact.

Changed
-------

- ``sendDefaultPii``, ``dist``, ``normalizeDepth`` and the three scrubbing
  handlers (``beforeSend``, ``beforeSendTransaction``, ``beforeBreadcrumb``),
  along with the integration list and the trace-header allowlist, are pinned
  *after* the backend-supplied ``diagnostics.sentry`` block is merged into the
  client options. The bootstrap contract does not declare any of them today,
  but the frontend — not the backend payload — is the authority over the code
  that constitutes the privacy boundary.

Documentation
-------------

- **No operator action required.** With neither ``FEDERATION_SECRET`` nor
  ``ACCOUNT_ID_SECRET`` configured, no telemetry reference is emitted —
  ``organization_ref`` is ``null`` on the Colonel record, which is the default
  in dev and test — and nothing else changes; diagnostics remain off entirely
  unless ``DIAGNOSTICS_ENABLED`` is set.

- **New, optional:** ``TELEMETRY_REF_REGION`` declares the data-residency
  scope for the telemetry references — actor and organization alike. Set it
  only when several instances share ``FEDERATION_SECRET`` and serve different
  jurisdictions without using the regions feature — otherwise ``JURISDICTION``
  already supplies it. Any short stable label works (``eu``, ``us``,
  ``ca-central``); the value is never transmitted, only mixed into the
  derivation. Changing it re-keys every telemetry reference on that install,
  and declaring nothing is safe by design.

AI Assistance
-------------

- Claude built the telemetry boundary and its acceptance suite. Five
  adversarial passes were run against the work, each executing attacks against
  the tree rather than reading it. The recurring defect they caught was
  comments asserting privacy guarantees the code did not deliver — including a
  correlation-radius claim in the TypeScript contract that the Ruby derivation
  contradicted, and a residency guard that covered the raising fault but not
  the falsy one. A sixth pass added pseudonymous resource correlation and
  verified it end to end against the real Colonel schema; it executed a further
  30 surface claims and found one false — a comment claiming the reference was
  the only thing about that record reaching an event, when failing field paths
  and shape descriptors do too.
