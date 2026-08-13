CHANGELOG
=========

All notable changes to Onetime Secret are documented here.

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__, and
this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

.. _changelog-0.26.4:

0.26.4 — 2026-08-05
====================

Added
-----

- Organization Secret Activity now records custom-domain context, has a
  workspace audit-events interface, and can be enabled or disabled with
  ``ORGS_AUDIT_LOGS_ENABLED``. (#3642, #3975, #3976, #3985)

- Operators can configure Secret Activity collection and its retention cap.
  (#3992)

- The test suite now has isolated lanes and containerized services on 21xx
  ports. (#3980)

Changed
-------

- Environment terminology and configuration scoping are clarified. (#3986)

Fixed
-----

- Domain configuration is sanitized and constrained at the serializer
  boundary. (#3998)

- Muted sidebar text now meets the WCAG AA contrast floor. (#3994)

Security
--------

- Updated PostCSS to 8.5.23. (#4004)

.. _changelog-0.26.3:

0.26.3 — 2026-08-01
===================

Added
-----

- Support staff can now answer "why can't this user log in or create an
  account" without SSH access. A new read-only diagnose operation
  (``Auth::Operations::Customers::Diagnose``) aggregates every relevant
  signal for one identifier — customer record state, Rodauth account status,
  lockout and consecutive login failures, pending verification / reset keys,
  MFA enrollment, active sessions, the authentication audit log tail, and the
  login rate limiter — and derives a severity-ordered findings list naming
  the blocking condition (locked out, rate limited, unverified with a stale
  verification email, email drift from a half-completed change, SSO-only
  account, orphaned auth account, suspended, or nothing found in this
  region). It is exposed twice over the single implementation: the
  ``bin/ots customers diagnose IDENTIFIER`` CLI command and a new Account
  Diagnostics panel on the colonel customer detail page
  (``GET /api/colonel/users/:user_id/diagnostics``). Every section degrades
  independently, so simple auth mode (no SQL authdb) still renders the
  Redis-side read-out. Identifiers can be an email, extid, or Rodauth
  account id; any of them resolving to no customer is still diagnosed
  against the auth database rather than 404ing, so orphaned accounts rows
  and "nothing exists here — check the other regions" both come back as
  findings instead of dead ends.

- The reset-password-request rate limiter is now registered with the operator
  rate-limit tooling as two kinds, ``reset_request_ip`` and
  ``reset_request_email``. Both are now reachable from the two supported
  operator paths, which previously offered no way to clear a reset-request
  lockout — an operator whose deployment tripped the per-IP tier had to wait it
  out. ``bin/ots ratelimit keys <kind> <subject>`` EMITS the ``TTL``/``GET``/
  ``DEL`` command text for the pair without touching the datastore itself, so it
  clears a lockout only once piped (``| grep -v '^#' | valkey-cli``); the
  colonel ``GET /api/colonel/ratelimit/inspect`` and ``POST
  /api/colonel/ratelimit/reset`` endpoints read and delete those same keys
  directly, and the reset records an admin audit event. Subjects
  are the STORED form: the privacy-masked client IP (/24 IPv4, /48 IPv6) for the
  IP tier and the normalized address (strip + NFC + case-fold) for the backstop;
  a raw address or mixed-case login reads back as not set. Enforcement,
  key shapes and limiter defaults are unchanged.

- A password-reset IP-tier lockout now logs an operator hint when
  ``site.network.trusted_proxy`` is not enabled, naming the remedy
  (``TRUSTED_PROXY_ENABLED=true``, or a higher
  ``RESET_REQUEST_RATE_LIMIT_MAX_PER_IP``). In that configuration the resolved
  client IP is ``REMOTE_ADDR`` — the proxy's own address behind a reverse proxy —
  so every visitor shares one bucket and the lockout is deployment-wide rather
  than per-origin. The hint is a server log line only; it never appears in a
  response and does not vary on whether an account exists.

Changed
-------

- ``TTL_MAX_ANONYMOUS`` replaces ``PLAN_TTL_ANONYMOUS`` throughout. The old name
  implied a coupling to plan and billing state that no longer exists. It is
  still read as an alias for the anonymous ceiling when the new name is unset,
  but it is no longer read anywhere else — including its second, older job of
  setting the free-tier ``secret_lifetime`` fallback used when plan state is
  unavailable. That fallback now reads ``TTL_MAX_ANONYMOUS`` as well, so on a
  billing-enabled deployment one variable moves both values.

  **Operators on a billing-enabled deployment should rename the variable.** Left
  as-is, ``PLAN_TTL_ANONYMOUS`` still sets the anonymous ceiling via the alias,
  but the free-tier ``secret_lifetime`` fallback reverts to its 14-day default
  (``free_v1`` in ``etc/billing.yaml``). That fallback only applies when plan
  state is unavailable — an empty or uncached ``planid`` — and the anonymous
  ceiling is unaffected either way.

.. note::

   **Self-hosted operators:** the anonymous ceiling defaults to 7 days whether
   or not billing is enabled. Deployments with billing off previously allowed
   anonymous secrets up to the configured ``ttl_options`` maximum (30 days on
   stock config), so this is a behaviour change on upgrade. It is a default,
   not a limit — set ``TTL_MAX_ANONYMOUS=2592000`` to restore 30 days, or any
   value up to 365 days. Authenticated users are unaffected; their limits still
   come from their plan, and the 14-day free-tier gate is unchanged.

- **API v3 receipt shape cleanup.** Two long-standing wart fields are corrected
  in v3 only; v1 and v2 responses are byte-for-byte unchanged.

  - ``recipients`` is now ``null`` or an array of strings. The shared
    serializer emits a single ``", "``-joined string (and ``""`` when the
    secret was never emailed), so a client had to branch on the type; v3
    normalizes it at its own serialization boundary. An empty list is ``null``,
    not ``[]``. Note that ``details.recipient`` (the array echoing the
    submitted request) and ``recipient_name`` (an Incoming-secret display name)
    are different fields and are unchanged.
  - ``custid`` is removed from v3 receipt payloads. It is a deprecated creator
    identifier that new receipts never write, so it has been ``null`` on every
    record created since the identifier migration. Read ``owner_id`` instead —
    it was already present alongside it.

  Applies to every v3 endpoint that returns a receipt: secret conceal/generate,
  receipt read, burn, update, the receipt list, and the guest batch receipts
  endpoint.

Fixed
-----

- Restored the Free plan on the pricing page. ``GET /billing/api/plans``
  dropped every plan that had no prices, and the free tier is defined with
  ``prices: []`` — so it passed the ``show_on_plans_page`` gate and was then
  filtered out one line later, leaving the pricing page with only paid plans
  and no way to see what the free tier includes. This regressed when the
  endpoint was refactored to flat per-interval records (#3153) and contradicted
  the catalog loader, which persists price-less plans specifically so they can
  be displayed. The endpoint now emits a single record for a price-less visible
  plan (``amount: 0``, no Stripe price, ``month`` interval). Signed-in
  customers also see the Free tier in the workspace plan grid, where it acts as
  the downgrade path for an active subscription.

- Fixed the billing catalog losing the free tier whenever plans are loaded from
  ``billing.yaml`` rather than Stripe. The loader skipped price-less plans
  outright, so a deployment that started while Stripe was unreachable had no
  free tier in its catalog at all — affecting entitlement materialization as
  well as the pricing page. The same loader backs the billing test fixtures, so
  the entire billing test suite ran against a catalog with no free tier, which
  is why this went unnoticed. The loader now handles config-only plans through
  the same path the Stripe sync uses.

- The **Single Sign-On** controls on a domain's *Sign-in Settings* page
  (``/org/:orgid/domains/:extid/signin``) were gated on the wrong switch. They
  read the PLATFORM SSO flag (``AUTH_SSO_ENABLED``, resolved by the config
  serializer against the *current request's* domain — the canonical workspace
  host), while per-domain SSO is TENANT SSO, whose real authorities are
  ``ORGS_SSO_ENABLED`` plus the ``manage_sso`` entitlement. On any install with
  platform SSO off, the availability toggle and the "SSO" method radio rendered
  permanently locked even for an organization fully entitled to configure tenant
  SSO. This page was the only surface gating on that axis; the domains table and
  the organization SSO tab already used ``ORGS_SSO_ENABLED`` + ``manage_sso``,
  and it now matches them.

- **Data loss:** on a domain with no sign-in configuration, the form seeded its
  ``sso_enabled`` flag from that same platform SSO flag. Because the page
  auto-saves every change as a full-replacement ``PUT``, the first edit to *any*
  field — the mode switch, the email toggle — persisted ``sso_enabled: false``
  on installs with platform SSO off. That flips
  ``SigninConfig.sso_permitted_for?`` to false and takes the domain's working
  tenant SSO sign-in buttons down. The flag is now seeded from the backend
  authority for an unconfigured domain (``sso_permitted_for?``, which defers to
  the domain's SSO credentials), so materializing the seed leaves tenant SSO
  exactly as it was running. Structurally the same failure as the
  ``signin_enabled`` bug fixed in #3817. Domains already carrying a stored
  ``sso_enabled: false`` from this bug are **not** rewritten by this release.
  Recovering one in-app requires ``ORGS_SSO_ENABLED=true`` *and* the
  ``manage_sso`` entitlement — the conditions under which the toggle is
  operable; with tenant SSO disabled install-wide there is no in-app path, and
  the flag must be turned on first.

- The SSO availability toggle reported OFF whenever the org lacked ``manage_sso``
  or tenant SSO was disabled install-wide, even when the stored value was true
  and the domain's SSO was live. Those two are management gates — the runtime
  ladder (``SsoConfig.tenant_sso_unavailable_reason``) never consults them — so
  the toggle now reports the stored value and expresses the lock through its
  disabled state alone.

- In "One specific method" mode, a domain restricted to SSO rendered a method
  list with nothing selected whenever the SSO row was filtered out, hiding the
  domain's actual configuration. The SSO row now stays visible — locked, and
  still not re-selectable — when it is the current restriction.

.. note::

   Tenant SSO is off by default (``ORGS_SSO_ENABLED``, absent ⇒ ``false``).
   These controls are *correctly* locked on an install that has not set it;
   turning them on is an operator action, not a plan upgrade.

- The secret duration dropdown no longer offers a lifetime the server will
  quietly shorten. Secrets created without signing in are capped server-side at
  7 days, but the dropdown was built from the full configured list, so on a
  stock install a guest could pick "30 days", see no error, and get less. The
  applicable ceiling is now published in the bootstrap payload
  (``secret_options.ttl_max_anonymous`` for guests,
  ``organization.limits.secret_lifetime`` for signed-in users) and longer
  options are filtered out of the list. The guest ceiling is published on every
  deployment, self-hosted included, and reflects any ``TTL_MAX_ANONYMOUS``
  override, so raising or lowering it moves the dropdown with it. A remembered
  duration above the
  ceiling now falls back to the configured default instead of silently
  resolving to a shorter lifetime.

Security
--------

- Added rate limiting to the password-reset request endpoint. In full
  authentication mode ``POST /auth/reset-password-request`` was made
  enumeration-safe earlier (#3857) but retained an accepted response-timing
  residual; exploiting it statistically requires many requests per target
  address. The route now enforces a two-tier limiter before any account lookup
  runs: a tight per-client-IP cap (default 10 requests/hour, using the
  trusted-proxy-resolved, privacy-masked client IP so forwarded headers cannot
  spoof it) and a higher per-submitted-address backstop (default 30/hour,
  case-normalized) that bounds IP-rotating callers probing a single target.
  Both tiers key only on request-observable inputs — never on whether the
  address maps to an account — so the 429 response discloses nothing about
  account existence. This stacks with Rodauth's per-account resend throttle,
  which caps emails but not request volume per source. Configurable via
  ``site.authentication.reset_request_rate_limit`` /
  ``RESET_REQUEST_RATE_LIMIT_*``; enabled by default. (#3872)

- Closed the account-enumeration oracle in the invite signup endpoint
  (``POST /api/invite/:token/signup``). It previously returned a distinct
  ``account_exists`` error when the invited email already had an account,
  re-opening the oracle the AZ7 hardening removed from the sibling
  show-invite endpoint — exploitable by any registered user who invites a
  target address and probes the token. The endpoint now validates the
  password before any account-existence check (an invalid-password probe
  gets a byte-identical error whether or not the account exists) and
  collapses all existing-account outcomes — authdb pre-check, Redis
  pre-check, and the Rodauth create race — into one generic
  ``signup_unavailable`` error whose conditional message never confirms
  account existence. The frontend keys its sign-in fallback off that
  error_type instead of sniffing the message text, so the invitee UX is
  unchanged. Residual: with a valid password, "exists" remains
  distinguishable from a successful signup — inherent to any signup
  endpoint, and probing it is destructive and noisy (creates the account,
  emails the invitee); the per-IP ``InviteTokenRateLimiter`` bounds it.
  (#3856)

- **API v2 Basic auth now fails closed.** Routes that accept either API
  credentials or anonymous access (``auth=basicauth,noauth`` — secret conceal,
  generate, reveal, receipt read/burn/update) treated a chain of strategies as
  OR logic, so a request presenting *invalid* Basic credentials fell through to
  the anonymous strategy and succeeded: HTTP 200 with the secret created under
  no owner. A caller whose API key was wrong, revoked, or whose username was an
  organization ID or ``owner_id`` instead of the account email or customer ID
  (``ur…``) silently got anonymous behaviour — anonymous TTL, no receipt in
  their account, no error. Rejected credentials now produce 401 with the
  original failure reason. Requests that present no ``Authorization`` header at
  all are unaffected and remain anonymous.

- Anonymous secret TTLs are now bounded by a ceiling that is read on every
  deployment, closing a policy inversion where an anonymous request could
  outlive an authenticated free-tier one (which is denied above 14 days with an
  upgrade prompt). The ceiling defaults to 7 days; a configured ``ttl_options``
  maximum below it still wins, and with billing enabled the free-tier
  ``secret_lifetime`` limit applies as well. See the note below for the
  self-hosted override.

- A recipient email supplied without an account now raises 401 rather than a
  422 field-validation error, correctly signalling an authentication failure.

.. note::

   **Operators behind an htpasswd-style reverse proxy:** strip the
   ``Authorization`` header before proxying to ``/api/v2``. A forwarded proxy
   credential is now read as a presented API credential, and an *anonymous*
   request carrying one gets 401. Session-authenticated requests are not
   affected — a valid session cookie outranks a stray or cached
   ``Authorization`` header, so the web UI keeps working either way.

- **The anonymous secret TTL ceiling is now read on every deployment.**
  Previously it was derived from the free-tier plan limit, so it applied only
  where billing was enabled — leaving deployments with billing off with no
  anonymous ceiling at all, and an override (``PLAN_TTL_ANONYMOUS``) that was
  silently ignored on exactly those installs. The ceiling is now its own
  configuration value (``site.secret_options.ttl_max_anonymous``, env
  ``TTL_MAX_ANONYMOUS``), defaulting to 7 days, resolved through a single reader
  shared by TTL enforcement and the bootstrap payload that builds the duration
  dropdown. A configured ``ttl_options`` maximum below the ceiling still wins.
  With billing enabled, the free-tier ``secret_lifetime`` limit applies as an
  additional ceiling, which is what preserves the invariant that an anonymous
  caller never receives a longer TTL than an authenticated free-tier user.

- Extended the password-reset request rate limiter to simple authentication
  mode, the application default. The two-tier limiter added in #3872 was wired
  only into the Rodauth ``before_reset_password_request_route`` hook, which is
  loaded exclusively in full mode — so in a default install ``POST
  /auth/reset-password-request`` had no throughput cap at all, letting an
  unauthenticated caller mail-bomb arbitrary addresses and accumulate unbounded
  samples against the endpoint's accepted response-timing residual. The shared
  reset-request logic now enforces the same limiter itself, before the email
  format check and before any account lookup, using the same subjects as the
  full-mode hook: the trusted-proxy-resolved, privacy-masked client IP (tight
  tier) and the submitted address (higher backstop). Both tiers key only on
  request-observable inputs, so the 429 discloses nothing about account
  existence. Configuration is unchanged
  (``site.authentication.reset_request_rate_limit`` /
  ``RESET_REQUEST_RATE_LIMIT_*``, enabled by default) and now applies in both
  auth modes.

  **Upgrade note for simple-mode operators.** Because the limiter is enabled by
  default, an install that has never set
  ``site.authentication.reset_request_rate_limit`` starts throttling this
  endpoint after upgrading — previously only full-mode installs did. The per-IP
  bucket is the privacy-MASKED client network (/24 for IPv4, /48 for IPv6 — the
  raw address never survives the IP-privacy middleware, the same granularity as
  every other IP-keyed limiter here), so users sharing one NAT egress share one
  budget: 10 reset requests per hour by default, then a one-hour lockout for
  that network. Sites with dense NAT populations should raise
  ``RESET_REQUEST_RATE_LIMIT_MAX_PER_IP`` (or shorten
  ``RESET_REQUEST_RATE_LIMIT_LOCKOUT``); ``RESET_REQUEST_RATE_LIMIT_ENABLED=false``
  opts out entirely. The per-address backstop is unaffected by IP granularity.

  **Configure trusted-proxy resolution if you run behind a reverse proxy.**
  ``TRUSTED_PROXY_ENABLED`` ships as ``false``, and while it is off every
  forwarded header is ignored and ``REMOTE_ADDR`` is used directly — which
  behind nginx/Caddy/Traefik/an ingress is the *proxy's* address for every
  request. The per-IP tier then resolves to one bucket for the whole
  deployment, so 10 reset requests per hour from any users combined trip a
  site-wide lockout (and one caller can burn it deliberately). This is a
  property of every IP-keyed control here, not of this endpoint specifically,
  but the reset-request tier is keyed on IP alone, so it is the most exposed.
  Proxied deployments should set ``TRUSTED_PROXY_ENABLED=true`` with the
  matching ``TRUSTED_PROXY_MODE``/``TRUSTED_PROXY_CIDRS`` for their topology —
  after confirming the proxy overwrites client-supplied ``X-Forwarded-For``,
  since trusting that header from an untrusted hop makes the tier spoofable.
  Where that is not possible, raise the per-IP cap and rely on the per-address
  backstop, which is unaffected.

Documentation
-------------

- **API response field semantics documented.** ``docs/api/README.md`` now
  states which secret/receipt fields are deprecated, which are aliases, and
  which are commonly confused for each other:

  - ``custid`` is deprecated — read ``owner_id``. v3 omits it from receipt
    records entirely; v2 still emits it but it is null on every receipt created
    since the v0.24 identifier migration; v1 alone translates it back to an
    email address. The top-level ``custid`` in receipt-list responses is a
    different field — the requesting customer — and is unaffected.
  - ``record.metadata`` in v2 conceal/generate responses is an alias emitting
    the identical object as ``record.receipt``. v1 returns only ``metadata``,
    v3 returns only ``receipt``. The separate ``metadata_path`` /
    ``metadata_url`` aliases on receipt responses remain in v3.
  - ``recipients`` (obscured addresses on the receipt — a joined string in v2,
    an array or ``null`` in v3),
    ``details.recipient`` (an array echoing the submitted request values), and
    ``recipient_name`` (an Incoming-secret display name, null for standard
    secrets) are three distinct fields, now tabulated with their per-version
    types.

AI Assistance
-------------

- Feature implemented end-to-end (operation, CLI adapter, colonel endpoint,
  admin UI panel, specs) with Claude Code.

- Simple-mode reset-request rate limiting implemented end-to-end with Claude
  Code: the limiter call site, the integration and unit coverage, and the
  operator/audit documentation. The specs were then hardened against an
  adversarial review pass that found two of them passing under mutation, and
  that pass also surfaced the invalid-UTF-8 constructor path that bypassed the
  new counter.

- A follow-up review pass, also with Claude Code, examined four reservations
  raised against the change. Two did not survive contact with the code and were
  dropped: keying the tight tier on IP alone is correct here rather than
  inconsistent, and the raise_concerns/process lifecycle is enforced at a
  controller chokepoint rather than by convention. The pass instead found the
  registry gap that left a lockout unclearable, a documented recovery command
  that only printed text without touching the datastore, and a hint whose
  production call site no test pinned. Recovery procedures in this changeset
  were confirmed by clearing a seeded lockout key, not by reading help output.

.. _changelog-0.26.2:

0.26.2 — 2026-07-26
===================

Added
-----

- SSO can now be told to trust an identity provider's email claim for account
  linking, via a per-provider, opt-in, default-off flag:
  ``OIDC_TRUST_EMAIL_FOR_LINKING``, ``ENTRA_TRUST_EMAIL_FOR_LINKING``,
  ``GOOGLE_TRUST_EMAIL_FOR_LINKING``, ``GITHUB_TRUST_EMAIL_FOR_LINKING``, or the
  global fallback ``SSO_TRUST_EMAIL_FOR_LINKING`` (set to ``true`` to enable). When
  enabled for a provider, an SSO identity whose email matches an existing account
  is auto-linked to that account instead of being refused — restoring email-based
  SSO linking for self-hosted single-tenant operators who control both the app and
  the identity provider. It is off by default, applies only to the platform
  (environment-configured) SSO path, and is ignored on the multi-tenant (per-domain
  ``CustomDomain::SsoConfig``) surface by construction; a non-fatal boot-time warning
  fires if it is enabled while tenant SSO configs exist. Every auto-link is recorded
  as a ``warn``-level ``omniauth_email_linked_trusted_provider`` audit event. Enable
  it only where the same operator controls both the app and the IdP — trusting the
  email is equivalent to trusting the IdP never to mint a token bearing another
  user's address. (#3836, #3840)

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

- Each row of the admin customers table links directly to the customer's full
  detail page, so an operator can escalate without opening the drawer first. It
  is a real link, so middle-click and open-in-new-tab work.

- ``bin/ots org reconcile ORG`` re-applies an organization's billing and
  entitlement state from the CLI. The logic moved out of the colonel endpoint
  into a shared ``Onetime::Operations::Org::Reconcile`` operation, so the
  console and the shell now run the same code and emit the same single
  ``organization.reconcile`` audit event.

- ``bin/ots org create NAME --owner OWNER`` creates an organization owned by an
  existing customer, backed by ``Onetime::Operations::Org::Create``.

- ``bin/ots org transfer-ownership ORG NEW_OWNER`` hands an organization to
  another existing member. The new owner must already be a member — the command
  refuses rather than creating a membership and granting it ownership in one
  confirmation. The previous owner is demoted to ``admin`` by default
  (``--demote-to``); removing them would break customers whose default
  organization pointed there. Ownership moves ``owner_id`` but never
  ``created_by``, which stays immutable per ADR-012.

- ``bin/ots org entitlement show|grant|revoke|clear ORG`` inspects and manages
  operator entitlement overrides. ``show`` reports plan, overrides, materialized
  entitlements and any drift between them.

- ``bin/ots customers change-email`` changes an account's email address across
  both stores, backed by ``Auth::Operations::Customers::ChangeEmail``, with
  optional ``--reason`` / ``--ticket`` recorded in the audit detail. A matching
  colonel endpoint (``POST /users/:user_id/email``) is available for support.

- ``customers doctor`` gained three checks: ``auth_email_drift`` (the Rodauth
  account address and the Redis customer address disagree),
  ``org_email_index_stale`` and ``org_contact_email_stale``. The first is what
  makes a partially-applied email change detectable — the previous checks only
  compared Redis against Redis.

- Membership-level entitlement overrides are now operable outside a console
  (#3907, closing D19 of the #3731 CLI-over-Operations epic).
  ``OrganizationMembership`` has carried ``grant_entitlement`` /
  ``revoke_entitlement`` / ``clear_entitlement_overrides`` all along, with no
  adapter reaching them. A single shared operation
  (``Onetime::Operations::Memberships::EntitlementOverride``) now backs two new
  symmetric surfaces: ``bin/ots memberships entitlement grant|revoke|clear|show``
  (dry-run by default in the op, ``--yes`` gated, ``--json`` capable) and the
  colonel endpoints
  ``POST /api/colonel/organizations/:org_id/members/:member_id/entitlements/:action``
  / ``DELETE …/members/:member_id/entitlements/overrides``. The operation emits
  exactly one ``membership.entitlement.*`` audit event per applied change;
  adapters never audit. Overrides survive role changes, org plan changes and
  re-materialization, and never expire (matching org-level semantics; expiry is
  #3905).

Changed
-------

- The ``AUTH_ENABLED`` master switch now suppresses tenant SSO on custom
  domains. Previously an SSO-only custom domain (enabled SSO config, no
  sign-in config) kept advertising its Sign In link and completing the SSO
  flow even with ``AUTH_ENABLED=false`` — but with authentication disabled,
  session auth is never registered, so the resulting session was silently
  ignored everywhere. The masthead link, /signin page, domain settings API,
  and the SSO runtime route now all go dark together under a master kill.
  ``AUTH_SIGNIN=false`` intentionally still leaves tenant SSO available: it
  retires only password/email sign-in. (#3672)

- **Operators:** the auth log event ``omniauth_tenant_sso_not_enabled`` now
  carries a ``reason`` field naming the gate that rejected the SSO request —
  one of ``auth_disabled`` (``AUTH_ENABLED`` off), ``no_sso_config``,
  ``sso_config_disabled``, or ``sso_not_permitted`` (the domain's sign-in
  config withholds SSO). This replaces the ``sso_permitted`` field, which was
  briefly renamed to ``sso_available`` during this work; both are gone.
  Anything alerting or querying on ``sso_permitted`` / ``sso_available`` must
  be updated to ``reason``. (#3672)

- ``bin/ots domains repair``'s ``--force`` flag is now ``--yes`` (``-y`` /
  ``-f``), and the command defaults to a confirmation prompt.

- ``bin/ots domains repair`` now exits non-zero on failure paths that previously
  exited 0: domain not found, an orphaned domain invoked without ``--org-id``,
  and a stale organization reference. Runbooks that treated exit 0 as success
  will start failing on these — correctly, since nothing was repaired. Passing
  ``--org-id`` for a domain that is *not* orphaned is now a hard error pointing
  at ``domains transfer``; it was previously accepted and silently ignored.

- ``bin/ots domains probe --timeout`` now takes effect. dry-cli does not coerce
  ``type: :integer``, so the value arrived as a string and raised inside the
  HTTP timeout path — every non-default ``--timeout`` was broken. The value is
  now coerced and validated.

- ``bin/ots domains doctor --repair`` now fixes a missing ``org.domains``
  membership through the same ``Operations::Domains::Repair`` operation the
  ``domains repair`` command and the colonel endpoint use, rather than writing to
  the sorted set directly. That means the repair is now recorded as a
  ``domain.repair`` admin audit event, and it is now blocked (loudly, per domain,
  without aborting an ``--all`` scan) when the domain already belongs to a
  different organization — the raw write bypassed that guard. Detection is
  unchanged and still O(1) per domain. Two operational consequences: the sorted
  set score for a *repaired* entry is now the repair time rather than the
  domain's creation time, which can reorder that entry in listings; and a repair
  that fails is reported under a new ``failed_repairs`` key and makes the command
  exit non-zero even when other domains were fixed.

- ``bin/ots domains doctor`` now reports domains with no organization at all
  (orphans) as a HIGH finding, pointing at ``domains repair --org-id``. It never
  repairs them — assigning an organization stays a human decision. Doctor
  previously skipped orphans entirely, so ``doctor --all`` gave a knowingly
  incomplete picture unless the operator also ran ``domains orphaned``. On an
  install that has orphans, ``doctor --all`` will now exit non-zero where it
  previously exited clean.

- ``org reconcile`` now does something on billing-disabled (self-hosted)
  installs. It previously reached the billing engine, found no plan, and
  returned without acting. It now materializes the standalone entitlement set
  and re-materializes every membership, returning a ``standalone`` status. This
  is reached through the existing colonel endpoint as well as the new CLI verb,
  and it cascades to every member of the organization.

- Confirming a self-service email change no longer sweeps sessions by scanning
  the keyspace. It delegates to the same index-based revocation operation used
  elsewhere. The old scan-first approach could exhaust its scan budget before
  reaching the target account's sessions and still report success, which at
  production account volumes meant sessions could survive an email change.

- ``ots server`` now applies its "config file or command-line options, but not
  both" rule to ``--threads`` and ``--bind``, which previously escaped it
  entirely: ``ots server --threads 4:8 config/puma.rb`` was silently accepted
  and the thread setting discarded. The rule compares against declared defaults,
  so passing an option set to its default value alongside a config file is
  accepted. ``--server`` and ``--environment`` remain unguarded.

Removed
-------

- ``bin/ots domains bulk-repair`` is gone. It now prints ``use: bin/ots domains
  doctor --all --repair`` and exits non-zero. The old command was wrong in two
  ways a compatibility wrapper would have preserved: its membership test compared
  an array of domain *objects* against a domain id *string*, so it was always
  false and every org-owned domain in the install was reported as "mismatched"
  and then "repaired"; and its mutation loop recorded no admin audit event at
  all. ``domains doctor --all --repair`` covers the same ground with a correct
  test, an audited repair, and index checks bulk-repair never had. Orphaned
  domains still need a per-domain decision via ``bin/ots domains repair DOMAIN
  --org-id ORG``.

Fixed
-----

- Restored a supported path for email-based SSO account linking on self-hosted
  single-tenant installs, which the H-3 security hardening in 0.26.0 removed. If you
  upgraded to 0.26.0 or 0.26.1 and SSO logins now bounce back to ``/signin`` with a
  generic "SSO authentication failed" message, the callback is refusing to auto-link
  an SSO identity to an existing account located only by email. This affects any
  account with no ``account_identities`` row for the exact ``(provider, uid)`` being
  presented: freshly created or seeded accounts, password-first users signing in with
  SSO for the first time, deployments that renamed a provider route (which changes the
  stored ``provider`` string and orphans every prior link at once), and IdP
  migrations. To resolve: on a single-tenant install where you control both the app
  and the IdP, enable the trusted-IdP linking flag described above; otherwise sign in
  with the account's existing method. The multi-tenant refusal is unchanged and
  intended. (#3836, #3840)

- Restored SSO login on Chromium-family browsers (Chrome, Edge, and others),
  which broke in v0.26.0-rc1. The emitted Content-Security-Policy contained
  ``form-action 'self'``, and because Chromium enforces ``form-action`` across
  the entire redirect chain, the SSO form-POST that hands off to the identity
  provider was blocked — clicking a provider button did nothing. Firefox was
  unaffected because it only checks the initial, same-origin form target. The
  app now adds each active SSO provider's IdP origin to the ``form-action``
  directive at boot, so the redirect is allowed. For sovereign clouds, an OIDC
  issuer whose authorization endpoint lives on a different origin, or org-level
  SSO with placeholder providers, additional origins can be supplied via
  ``SSO_FORM_ACTION_ORIGINS`` (space-separated). Operators who cannot yet
  upgrade can set ``CSP_ENABLED=false`` as an interim workaround to drop the CSP
  header entirely. (#3848)

- Hardened the ``add-msg-issue-prefix`` commit hook (bumped to
  ``v0.1.1-fork``): it no longer mistakes version tokens in branch names for
  issue IDs (``fix/...-v4-...`` stamped ``[#V4]``), no longer double-prefixes
  ``[#I18N]`` commits on reword, and now emits a bare number for ``issue-1234``
  branches. Adds a dedicated ``--tag-pattern`` so tag detection no longer
  depends on the branch-extraction regex. (#3891)

- Colonel admin endpoints that document an "email or extid" identifier now
  actually accept an email address. The shared identifier sanitizer stripped
  ``@`` and ``.``, so ``user@example.com`` arrived at the lookup as
  ``userexamplecom`` and the request failed with "not found". This affected
  adding a member to an organization, changing or removing a membership, and
  the verify / unverify / purge / detail user endpoints.

- The colonel customer detail page no longer times out. Its secrets and receipts
  read-outs walked the entire ``secret:*`` / ``receipt:*`` keyspace, loading every
  object one at a time to filter by owner; the 10,000-item guard counted MATCHES
  rather than keys scanned, so it never tripped for a normal account and the walk
  ran to completion on every page load. Both sections now read a bounded,
  newest-first page from a per-owner index — receipts from the existing
  ``customer:<id>:receipts`` set, secrets from a new ``customer:<id>:secrets``
  index written at the same two chokepoints as the ``secrets_active`` counter, so
  the two can only drift together. Accounts whose secrets predate the index fall
  back to a scan that is bounded by scan rounds *and* a wall-clock deadline, and
  any partial result is reported to the UI as such rather than rendered as if it
  were the whole record. A slow or failing activity lookup now degrades that
  section alone — identity, plan, role, organization and billing still render.

- Revealing an email address in an admin table no longer also opens the row's
  detail drawer. The reveal toggle and its copy button now contain their own
  clicks, which fixes the same interaction across every console table that
  renders an obscured address inside a clickable row.

- Saving a domain's homepage configuration no longer hides the branded
  masthead Sign In / Create Account links for the admin's own session until
  the next page reload. The save response echoes deprecated stored fields
  that carry no display authority, and these were overwriting the live
  resolver-computed values in the session bootstrap state. (#3672)

- Numeric ``bin/ots`` options now take effect. Dry::CLI does not implement
  ``type: :integer`` or ``type: :float`` — the symbols are accepted and ignored
  — so a supplied flag reached the command as a string while an omitted one kept
  its declared numeric default. Every such option was bimodal, and eleven were
  outright broken: ``ots status --watch`` and ``ots queue status --watch``
  (``TypeError`` from ``sleep``, so watch mode never worked at all),
  ``ots queue dlq replay --count`` and ``ots housekeeping run --limit``
  (``ArgumentError`` from a comparison), ``ots domains list --limit``,
  ``ots domains verify --limit``, ``ots organizations --list --limit``,
  ``ots billing products events --limit`` (``TypeError`` from ``Array#take`` /
  ``Array#first``), ``ots billing webhooks replay --limit``, and
  ``ots banner set --ttl``. ``ots queue dlq show --index`` silently matched
  nothing.

- Non-numeric input to a numeric option is now rejected with a clear message and
  a non-zero exit instead of being passed through untouched. Previously
  ``--limit abc`` reached the underlying operation as the string ``"abc"``; in
  ``ots bannedips ban --expiration abc`` it became a permanent ban, and in
  ``ots email sync-feedback --limit abc`` it silently requested the 5000-record
  maximum. Values are parsed as base 10, so ``--timeout 010`` means 10 rather
  than octal 8.

- An operator-initiated email change that could not reset the account's
  verified state no longer reports success. Previously the reset was
  best-effort: if it failed, the change still returned success and the account
  stayed marked verified on an address nobody had proven ownership of. The
  verified flag is now cleared directly (scoped to the account's own row, and
  only when that row is actually marked verified, so it can never revive a
  closed account), and if even that cannot be confirmed the change reports
  ``verification_not_reset`` — the CLI exits non-zero and names the remediation,
  and the colonel endpoint refuses to answer 200.

- The same reset is no longer skipped when the two stores disagree about
  verification. It previously short-circuited on the Redis mirror alone, so an
  account whose authoritative auth-database row still said "verified" was left
  untouched with no warning at all.

- In simple (Redis-only) mode, the email address is now claimed atomically
  before the customer record is re-keyed. Previously a concurrent signup or
  email change that claimed the same address in a narrow window had its index
  entry silently overwritten, leaving one of the two accounts unreachable by
  email. In full mode the auth database's unique constraint already served this
  purpose and continues to.

- ``bin/ots domains doctor`` no longer reports every stale
  ``display_domain_index`` entry twice. It ran two byte-identical passes over the
  same index hash with the same predicates, differing only in the severity and
  key they reported under, so N stale entries surfaced as N HIGH findings *and* N
  MEDIUM findings. With ``--repair`` the second pass also re-deleted each field
  and appended a second ``repaired`` record, so the summary and the ``--json``
  report both claimed 2N repairs for N real problems. There is now one check, at
  HIGH severity, reporting under ``display_domain_index_stale`` and repairing
  under ``display_domain_index_cleaned``. The ``display_domain_index_hash_stale``
  finding and the ``display_domain_index_hash_cleaned`` repair action no longer
  exist — anything parsing the ``--json`` report for those keys should read the
  non-``_hash`` ones. The doctor's numbered check list shifts accordingly (the
  org.domains membership check is now #4, orphan reporting #8).

- The colonel entitlement-override endpoints rejected a malformed action with
  "Action must be grant or revoke", which is wrong on ``DELETE
  /api/colonel/organizations/:org_id/entitlements/overrides``: that route carries
  no action parameter and maps to the ``clear`` action, which the operation has
  always accepted. The message is now derived from the operation's ``ACTIONS``
  constant so it cannot drift again, and reads "Action must be one of: grant,
  revoke, clear".

- Four CLI command files (``domains probe``, ``domains repair``, ``org create``,
  ``org transfer-ownership``) included a shared helper module they never
  required, so they only loaded successfully because ``lib/onetime/cli.rb``
  happened to require the helper first. Loaded directly, or after any reordering
  of that manifest, they raised ``NameError`` at class-definition time. Each file
  now requires its own dependencies.

Security
--------

- Closed an account-enumeration oracle on the password-reset request endpoint.
  In full authentication mode the Rodauth-backed
  ``POST /auth/reset-password-request`` answered a request for a registered
  address differently from an unregistered one — and differently again for an
  unverified account or one that was emailed moments earlier — letting an
  unauthenticated caller probe which email addresses have accounts (CWE-204).
  The endpoint now returns the same generic "an email has been sent" response in
  every case, matching the enumeration-safe behavior the basic-mode endpoint
  already enforced, while still sending a reset email only for a valid, verified
  account and preserving Rodauth's resend throttle. A residual response-timing
  difference remains — a matching account performs additional database writes and
  an email dispatch that a non-existent address does not — and is a known, accepted
  limitation: it reduces the leak from a definitive single-request answer to a
  timing-only signal, and closing it fully would require request padding or dummy
  work that adds abuse surface on an unauthenticated route without robustly
  removing it. (#3857)

- Re-keyed admin verification updates off bare email. In full authentication
  mode, ``SetCustomerVerification`` updated the Rodauth ``accounts`` row with
  ``WHERE email = ?``, but the unique index on ``accounts.email`` is partial
  (``status_id IN (1, 2)``), so a Closed account can share a live row's
  address. A plain ``bin/ots customers verify`` (or the colonel endpoint) would
  then silently resurrect a Closed account (status 3 → 2) when no live sibling
  existed, or die with an unhandled ``Sequel::UniqueConstraintViolation`` when
  one did — leaving that customer permanently un-verifiable through every admin
  surface. The update is now keyed on the ``external_id``-linked row (rows
  left unlinked by a failed signup-time link fall back to email restricted to
  live, unlinked rows), constrained to live statuses so a Closed row is never
  touched, and a new ``AccountClosed`` error is reported cleanly by the CLI and
  colonel surfaces instead of a stack trace. The self-service Rodauth
  ``after_verify_account`` path was never affected. (#3916)

.. _changelog-0.26.1:

0.26.1 — 2026-07-21
====================

Added
-----

- Configurable and validated Stripe checkout-host allowlisting for custom domains.
  (#3821)

- Brand-pack resolution diagnostics in the CLI, Colonel API, and admin console,
  including operator runbook guidance. (#3822, #3825)

- Receipt status UI now surfaces receipt access telemetry. (#3829, #3832)

Fixed
-----

- Password changes now invalidate stale sessions and reject sessions authenticated
  before the credential watermark, preventing session fixation. (#3810, #3830)

- The pricing-page **Current** badge now selects the active plan by plan ID.
  (#3824, #3827)

.. _changelog-0.26.0:

0.26.0 — 2026-07-20
======================

Added
-----

- The HTML head now emits a full favicon set: SVG favicon, Apple touch icon,
  PWA web manifest + icons, Safari pinned-tab mask icon, and Open Graph /
  Twitter ``og:image``. Per-custom-domain favicons still take precedence.
  (#3048, #3049)

- The favicon generator (``scripts/branding/``) is now a reusable, parameterized
  tool: glyph, palette, manifest name, sizing, and an optional license credit
  are all overridable via env vars or named presets (``--preset <name>`` /
  ``MARK_PRESET``), with a dependency-free test suite
  (``pnpm run gen:favicons:test``).

- Optional Onetime Secret company-brand favicon pack ships as the first preset
  (``pnpm run gen:favicons:maruhi``), rendering the "maruhi" (circled 秘) mark
  through the shared generator. Brand-neutral defaults in ``public/web/`` are
  untouched. (#3048, #3049)

- New ``BRAND_LOGO_ALT`` / ``brand.logo_alt`` setting for operator-supplied
  brand-logo alt text; falls back to an i18n string derived from the product
  name when unset. (#3612)

- Custom domains can now present the Incoming Secrets form as their public
  homepage, via a three-way Homepage selector — private landing page, secret
  creation form, or incoming secrets form (stored as ``secrets_mode`` on the
  per-domain HomepageConfig). The incoming option requires incoming secrets
  enabled with at least one recipient, and fails closed to the private landing
  page if that later lapses. Existing domains are unaffected.

- Access telemetry on the receipt: every fetch of a secret's link or status is
  recorded as an append-only event on the receipt's access timeline. Receipt
  details now expose ``view_count`` (previously always ``null``),
  ``first_access``, and ``last_access``, so creators can see whether and when a
  link was accessed even after the secret is consumed. (#3633)

- Organization audit trail: secret activity for receipts created in an
  organization's context (creation, link/status fetches, reveal, burn, expiry)
  is recorded to a per-organization audit stream, exposed via
  ``GET /api/organizations/:extid/audit-events`` (paginated, newest first).
  Requires the ``audit_logs`` entitlement, granted to admins and owners on
  qualifying plans. Events carry receipt/secret shortids only, never full
  identifiers. (#3633)

Changed
-------

- Updated the favicon/icon/social defaults to be brand-neutral. Regenerate with
  ``pnpm gen:favicons``.

- The custom email sender form now pre-fills ``no-reply@<domain>`` and the
  organization name for domains without a saved configuration.

- The custom email sender's address-field placeholder is now localizable.

- The neutral product name on unbranded installs is now "Secure Links" instead
  of "My App", across the UI and the PWA manifest. Installs that configure
  ``BRAND_PRODUCT_NAME`` or per-domain branding are unaffected.

- Viewing a secret link no longer resets the secret's expiration; secrets now
  always expire on their original schedule regardless of how often the link is
  viewed.

- The ``brand:`` config block is now the single authority for brand identity:
  ``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``, and ``BRAND_LOGO_ALT`` brand the
  masthead, outbound emails, page titles, and MFA labels. ``BRAND_LOGO_URL`` now
  drives the masthead operator logo too (previously email-only); emails emit
  only absolute http(s) logo URLs, degrading to a text-only header otherwise.
  (#3612)

- The header config is reduced to masthead layout knobs under
  ``site.interface.ui.header.logo`` — ``href`` (``LOGO_LINK``), ``show_name``
  (``LOGO_SHOW_NAME``), and ``prominent`` (``LOGO_PROMINENT``). ``show_name``
  unset now means "show the wordmark unless a custom brand logo is configured".
  (#3612)

- Unconfigured installs now present a fully neutral identity — the "Secure
  Links" name and keyhole mark — instead of the old "One-Time Secret" defaults.
  (#3612)

- TOTP/MFA entries now use the configured product name as the issuer label when
  ``BRAND_TOTP_ISSUER`` is unset. (#3612)

- Custom-domain screens no longer show Approximated-based DNS status badges on
  installs that don't use the ``approximated`` validation strategy. Adding a
  domain on such installs now opens a simple DNS-setup screen showing the CNAME
  record to point at the canonical domain.

- Secret-link and incoming-secret emails render the secret's custom domain in
  the shared layout's header wordmark and footer link. Account and system
  emails still use the canonical host.

- Custom-domain homepages no longer show the **Create Account** and **Sign In**
  nav links by default; the per-domain ``signup_enabled`` / ``signin_enabled``
  toggles now default to *off*. Operators re-enable the links per domain via
  ``PUT /homepage-config``. The authentication kill switch is unchanged — this
  only narrows what is displayed, never widens capability. (#3618)

- **Action Required**: existing custom domains have these flags persisted as
  ``true``, so a code-only default change cannot reach them. A data migration
  resets the stored values; run it during deployment::

      bin/ots migrate --run 20260703_01_disable_homepage_auth_links

  The migration is idempotent and preserves each domain's homepage ``enabled``
  setting. (#3618)

- ``GET /api/incoming/config`` on custom domains now reports ``enabled: false``
  when the domain's incoming config has no recipients, so the /incoming page
  shows its disabled state instead of an unsubmittable form.

- Reading a secret no longer changes it: ``GET /secret/:identifier`` and
  ``/status`` (v2 and v3) no longer advance the secret from ``new`` to
  ``previewed`` as a side effect. Lifecycle state now advances only on a genuine
  reveal or burn. (#3633)

- ``previewed`` is retired as a receipt lifecycle *state* — new receipts move
  ``new -> revealed/burned/expired/orphaned`` only. The creator's own
  secret-link open is now surfaced from the access timeline (``view_count`` /
  ``first_access``) rather than a mutated field. The ``is_previewed`` attribute
  now means "the link has been accessed at least once", keeping the receipt page
  and dashboard working unchanged. Legacy ``previewed``/``viewed`` records still
  report ``true``. (#3633)

- The legacy v1 secret and receipt read endpoints no longer advance state on a
  GET, matching v2. (#3633)

- The V1 API receipt endpoint no longer reveals a concealed (user-supplied)
  secret's plaintext to the creator, aligning V1 with V2/V3: only generated
  values are shown, only on first view, and only within the display TTL.

Deprecated
----------

- ``SITE_NAME``, ``LOGO_URL``, and ``LOGO_ALT`` (the
  ``site.interface.ui.header.branding`` path) are deprecated in favor of
  ``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``, and ``BRAND_LOGO_ALT``. Legacy
  values are still honored as fallbacks; boot logs a warning but never refuses
  to start. (#3612)

Removed
-------

- The legacy v1 API is now strictly JSON-only. Its hand-rolled
  Content-Security-Policy, per-request nonce, and unused HTML-response
  capability are removed; CSP is owned solely by Otto's response layer.

- The 32 tuning/toggle ``JOBS_*`` environment variables (per-job ``enabled``,
  ``interval``, ``batch_size``, ``cron``, ``*_hours``, ``sample_size``,
  ``rate_limit``, ``auto_repair``, …) no longer take effect; their defaults are
  now inlined in ``etc/defaults/config.defaults.yaml``. Tune these jobs via the
  ``jobs:`` block of your ``etc/config.yaml`` override instead. The three
  deploy-time switches — ``JOBS_ENABLED``, ``JOBS_FALLBACK_SYNC``, and
  ``JOBS_SCHEDULER_ENABLED`` — remain env-overridable. (#3775)

Fixed
-----

- The global authentication kill switch (``AUTH_ENABLED`` / ``AUTH_SIGNIN`` /
  ``AUTH_SIGNUP``) is now authoritative over per-domain sign-in and sign-up
  configuration. Previously an enabled per-domain ``SigninConfig`` /
  ``SignupConfig`` could re-enable sign-in or sign-up on a custom domain even
  while the operator had disabled it globally; a domain config may now only
  narrow, never widen, the install-level setting. (#3453)

- Schema validation failures now name the field that failed — in the log message
  and a searchable ``schemaField`` Sentry tag (paths and codes only, never
  values). (#3424)

- A transient or schema failure on the secret reveal page is no longer shown as
  "this secret has been viewed or expired"; only a genuine 404 shows that, while
  load errors get a distinct, retryable message. (#3424)

- Receipts no longer fail to load when a numeric or timestamp field is
  string-typed at rest; ``ShowReceipt`` coerces the affected fields at the
  boundary, and ``expiration`` may now be null for a consumed or expired secret.
  (#3424)

- Czech and Dutch UI copy that had drifted out of each locale's informal
  register is corrected (13 Czech strings to informal ``ty``; 34 Dutch strings
  to informal ``je``/``jouw``). (#3530)

- A ``fallback: :sync`` email delivery failure (e.g. an unreachable SMTP host
  while background jobs are disabled) no longer returns HTTP 500 after the record
  was already persisted. Synchronous fallback now blocks and delivers, logging a
  failure instead of raising, so organization invitations, email-change requests,
  password resets, and Rodauth auth emails degrade gracefully and stay
  resendable. (#3486)

- The default logo and the unbranded disabled-homepage fallback now use the
  neutral keyhole mark instead of OneTimeSecret's "maruhi" (秘) branding, so
  private-label and custom-domain deployments no longer leak OTS branding.
  (#3048, #3049)

- Replaced several hardcoded OneTimeSecret brand colors (the disabled-homepage
  accent dot, decorative gradients, and a button shadow) with brand design
  tokens, so they follow per-domain branding.

- Unbranded domains now default to light button text instead of dark, matching
  the neutral brand contract. Clearing the primary color in the branding
  live-preview also resets the button-text contrast.

- Branded logo accessibility: the custom-domain masthead logo now has a
  meaningful ``alt`` (the brand name), and the default logo no longer announces
  its label twice to screen readers.

- The custom-sender API no longer rejects a blank ``from_address``; it now
  defaults to ``noreply@<domain>``, matching the frontend default.

- The disabled-homepage page no longer renders a stray rectangular surface
  behind its centered content in light mode.

- A password-reset request for a pending (unverified) account no longer returns
  a 500; ``send_verification_email`` now accepts the recipient explicitly, so
  the resend succeeds and returns the same generic success as every other case.
  (#3486)

- Custom domains with no uploaded logo no longer show the platform's site name
  beside the fallback logo; page titles and social-share meta tags fall back to
  the configured brand name instead of a hardcoded "Onetime Secret". (#3566)

- ``scripts/branding/mark.mjs``'s ``MARK_PATH`` glyph override no longer
  mis-scales glyphs whose native size isn't the keyhole's 512x1024; native
  bounds are now configurable via ``MARK_NATIVE_WIDTH`` / ``MARK_NATIVE_HEIGHT``.

- The Content-Security-Policy header is now emitted on web (HTML) responses by
  default. It was previously gated behind ``CSP_ENABLED=true`` and so not output
  as intended. Set ``CSP_ENABLED=false`` to opt out.

- The operator/install logo no longer leaks onto tenant custom domains: they
  show their own uploaded logo or the neutral mark. (#3612)

- Incoming secrets (``/incoming``) submitted on a custom domain are now bound to
  that domain: the notification email links to the secret on the custom domain
  and is delivered via that domain's sender config.

- ``Receipt#expired!`` now has a state guard, so a later view of an
  already-expired receipt no longer re-runs the transition (redundant writes,
  duplicate log and audit entries). (#3633)

- Viewing a secret's receipt/metadata page no longer mutates the secret's
  lifecycle state. The receipt-page GET previously flipped the receipt to
  ``previewed``; it now records a one-time ``receipt_viewed`` audit event
  instead, claimed atomically so simultaneous first-loads record exactly one.
  (#3633)

- A generated secret's plaintext is now shown to its creator on the receipt page
  *exactly once*. Retiring the ``previewed`` state mutation had left the value
  re-displayable on every reload; both v1 and v2 paths now claim the display
  atomically, so a repeated or concurrent load never re-reveals the value.
  (#3633)

- Checkout session creation now sends a fresh UUID idempotency key on every
  attempt instead of a deterministic time-bucketed key. Customers who retried
  checkout within the same window previously received Stripe's cached (possibly
  already-completed) session, and changed parameters raised
  ``Stripe::IdempotencyError``. Duplicate *completions* remain deduplicated by
  the ``checkout.session.completed`` webhook handler; mutation calls such as
  plan changes keep their deterministic keys. (#2605)

- Checkout now blocks an organization that already owns a genuinely active,
  non-canceling subscription from starting a second checkout session (API and
  plan-redirect paths), and the ``checkout.session.completed`` handler loudly
  logs a completed checkout that would overwrite a different, still-active
  subscription. This closes a duplicate-subscription hazard (double charge plus
  an orphaned, still-charging subscription). Currency-migration and
  resubscribe-after-cancel flows remain exempt. (#2605)

- The notifications worker's prefetch default in
  ``etc/defaults/config.defaults.yaml`` now reads ``5`` instead of ``10``,
  matching the value the worker actually runs with. No runtime behaviour change
  for a default deployment. (#3777)

Security
--------

- Password-reset requests no longer reveal whether an email address has an
  account (CWE-204). A well-formed but unregistered address now gets the same
  generic success response, with no reset secret created and no email sent.
  (#3486)

- The hardened config and logger YAML loaders now permit ``Date`` and ``Time``
  in addition to ``Symbol``. Previously an unquoted date or time in a
  deployment's ``config`` or ``logging`` YAML (e.g. ``expires: 2026-01-02``)
  raised ``Psych::DisallowedClass`` and prevented boot; arbitrary Ruby objects
  (``!ruby/object``) remain rejected. (#3498)

- Fixed a double-reveal race on burn-after-reading secrets (CWE-362). Two
  concurrent requests to the same secret link could both decrypt and return the
  plaintext before either destroyed the record, disclosing a "view once" secret
  to more than one recipient. Revealing or burning now claims the secret with an
  atomic compare-and-set, so exactly one caller may consume it.

- A burn request that loses the race no longer counts toward burn metrics nor
  reports success to the caller.

- Closed a related re-exposure window: recording that a secret link had been
  viewed wrote the secret's state unconditionally, which could momentarily
  revert a just-revealed secret to a viewable state or recreate one a concurrent
  reveal or burn had destroyed. The transition is now atomic.

- Federated subscription benefits are no longer claimed before an account's
  email is verified. Previously a pending cross-region subscription (matched by
  email hash) was claimed during standard signup, before the verification email
  was even sent — letting someone who knew a subscriber's email register it in
  another region and claim the benefit. The claim is now deferred to
  ``after_verify_account`` when email verification is enabled. SSO, invite, and
  post-payment flows are unaffected.

- Federated subscription claims made without email verification (deployments
  with ``verify_account`` disabled, an unavoidable residual of that
  configuration) are now surfaced by a loud, structured security-audit log
  recording the org, email-hash prefix, and plan. Happy-path behavior is
  unchanged.

.. _changelog-v0.25.11:

v0.25.11 — 2026-06-20
=====================

Fixed
-----

- Secrets and Receipts now guarantee a non-null integer ``lifespan``/TTL
  end-to-end, closing the null half of #3424. ``Receipt.spawn_pair`` coerces
  ``lifespan`` to an Integer (also fixing a latent ``lifespan * 2``
  string-multiply bug), and config normalization coerces
  ``features.incoming.default_ttl`` and hardens
  ``site.secret_options.default_ttl`` against any non-Integer. (#3424, #3299)

- **SSO sign-in no longer freezes when the IdP returns no usable email.** The
  OmniAuth callback now redirects to ``/signin?auth_error=invalid_email`` and
  the sign-in page renders a localized error (unrecognized codes fall back to a
  generic SSO-failure message) instead of a blank/"frozen" screen; the callback
  guard also rejects an empty local part (``@example.com``) so it can no longer
  fall through to account creation and 500. A stable identifier fallback for
  emailless SSO users is tracked separately. (#3478)

.. _changelog-v0.25.10:

v0.25.10 — 2026-06-13
=====================

Added
-----

- ``scripts/diagnostics/detect_string_typed_numerics.rb``, a read-only scan that
  finds Secret/Receipt records whose numeric fields are stored as JSON strings
  at rest (the corruption behind #3424). (#3424)

- One-click SSO on the disabled-homepage variants (``minimal`` and ``v1``): when
  SSO is the sole login method and a single provider is configured, the homepage
  shows a direct SSO sign-in button instead of a ``/signin`` link. (#3433)

- ``scripts/ip_privacy_trusted_proxy_repro.rb``, a standalone diagnostic for the
  trusted-proxy harmonization follow-up. (#3427)

Changed
-------

- The disabled-homepage ``legacy`` variant is renamed to ``closed`` and is now
  the default. Self-hosters who pinned ``minimal`` or relied on the ``legacy``
  name should update their disabled homepage configuration. (#3433)

- Corrected the MFA recovery-code generation comment (codes are a CSPRNG-backed
  64-bit base36 token, ~13 chars, not 8-character ``36^8``). No change to the
  generated codes. (#3455)

Fixed
-----

- Secret and Receipt API responses now coerce their numeric fields at the
  ``safe_dump`` boundary: TTL/lifespan fields cast to integers,
  ``created``/``updated`` timestamps cast to floats (preserving the sub-second
  precision used as sorted-set scores). Records whose numeric fields were ever
  written as strings previously failed the strict ``z.number()`` V3 schema, so
  recipients saw "That information is no longer available" and senders'
  dashboards stuck on "Previewed". (#3424, #3268)

- MFA enrollment QR codes now encode the secret the server actually validates.
  With HMAC mode the frontend was reconstructing the ``otpauth://`` URI from
  ``otp_raw_secret`` instead of ``otp_setup``, so scanned codes never matched;
  the backend now emits Rodauth's authoritative ``provisioning_uri``. (#3431)

- Behind a trusted proxy, the IP-privacy middleware now masks the real client IP
  instead of the proxy's. It previously resolved ``REMOTE_ADDR`` and overwrote
  the forwarded headers before any later strategy could read the client IP; it
  now trusts private proxy ranges when ``site.network.trusted_proxy.enabled`` is
  true. Public-egress CDN ranges still need CIDR matching, which the
  prefix-based list does not do. (#3427)

- The burn endpoints (v1 and v2) now honour ``continue=false``. Both parsed the
  flag into a boolean but computed ``greenlighted`` from the raw
  ``params['continue']``, so the string ``"false"`` (truthy in Ruby) burned the
  secret anyway. The greenlight check now uses the parsed boolean.

- The "Receipt state transition" audit log lines now record the actual secret
  identifier. ``revealed!``/``burned!``/``expired!`` cleared
  ``secret_identifier`` before building the log payload, so every event logged
  ``secret_id: ""``; the identifier is now captured before it is cleared.

- ``Onetime::Utils.strand`` now draws every character of a generated secret from
  ``SecureRandom``. The complexity branch previously used ``Array#sample`` and
  ``Array#shuffle`` (non-cryptographic Mersenne Twister). No change to length,
  character sets, or the one-char-per-set guarantee. (#3452)

- MFA OTP setup now fails visibly instead of advancing to a blank QR scan step
  when a setup response omits ``provisioning_uri`` (the non-HMAC path previously
  did this silently). (#3455)

.. _changelog-v0.25.9:

v0.25.9 — 2026-06-09
====================

Added
-----

- **On-demand heap dumps**: opt-in ``SIGUSR2``-triggered heap dumps (via
  ``HEAP_DUMP_ENABLED``) for diagnosing process memory growth, with a
  ``scripts/analyze-heapdump`` analysis utility. (#3366)

Security
--------

- **Heap dump safety**: dumps are disabled by default, written owner-only
  (``0600``) via ``O_EXCL``, and may contain plaintext secrets. Treat dump files
  as sensitive credentials. (#3366)

AI Assistance
-------------

- Heap dump boot initializer, analysis script, and tests drafted with AI
  assistance. (#3366)

.. _changelog-v0.25.8:

v0.25.8 — 2026-06-06
====================

Added
-----

- **SSO self-heal**: Legacy users signing in via domain SSO now automatically
  adopt their domain organization as their default workspace. (#3336)
- **Organization soft-archival**: Added ``Organization#archive!``, ``archived?``,
  and ``unarchive!`` methods. (#3336)
- **Familia storage migration**: Added migration
  ``20260606_01_unique_index_json_to_raw`` to rewrite legacy JSON-encoded
  indexes to the raw format required by Familia 2.10, restoring broken
  custom-domain SSO lookups. (#3347)
- **Index validation**: Added a boot-time warning if any legacy JSON-encoded
  indexes remain, including the exact remediation command. (#3347)

Changed
-------

- Upgraded Familia to v2.10.1. Unique index keys are now stored as raw strings
  rather than JSON-encoded strings. (#3336, #3347)

Fixed
-----

- Tryouts calling writes on unsaved parent objects now save first, satisfying
  Familia v2.10's strict validation rules. (#3336)

.. _changelog-v0.25.6:

v0.25.6 — 2026-06-01
====================

Changed
-------

- **Config split enforcement**: ``CustomDomain#allow_public_homepage?`` and
  ``allow_public_api?`` now fail closed (returning ``false``) if their config
  records are missing, migrating away from the retired ``BrandSettings``
  fallbacks. (#3026)
- **Auto-bootstrapping configs**: ``CustomDomain.create!`` now automatically
  boots default-disabled ``HomepageConfig`` and ``ApiConfig`` records. (#3026)
- **Recipient configuration consolidation**: Removed legacy domain recipient
  endpoints and the ``IncomingSecretsConfig`` model; consolidated all recipient
  storage into ``CustomDomain::IncomingConfig``. (#3095)
- **Structured logger cleanup**: Narrowed ``Billing`` logs to payments, routing
  subscription entitlements to ``Ents`` logs (filterable via ``DEBUG_ENTS=1``).
  Unified database logging under ``DEBUG_DATABASE``. (#3257, #3274)

Removed
-------

- **Retired brand configurations**: Fully removed the legacy
  ``allow_public_homepage`` and ``allow_public_api`` fields from
  ``BrandSettings``, their API endpoints, frontend schemas, and admin views.
  (#3026)

Fixed
-----

- **Recipient management**: Fixed a bug where saving domain recipients
  overwrote existing entries, by moving to a merged PUT payload model. (#3095)

Deployment
----------

- **Action Required**: Operators must run the
  ``migrate_incoming_secrets_to_config`` housekeeping chore during deployment to
  migrate legacy recipient records before traffic resumes::

      bin/ots housekeeping run Onetime::CustomDomain migrate_incoming_secrets_to_config

  (#3095)

.. _changelog-v0.25.0:

v0.25.0 — 2026-04-29
====================

Changed
-------

- **Atomic invite acceptance**: Consolidated the invitation login flow to accept
  invitations atomically during login, eliminating race conditions and reducing
  API roundtrips. (#2897)
- **Atomic domain configuration**: Added ``find_or_create_for_domain`` to
  ``HomepageConfig`` and ``ApiConfig`` using Familia's atomic transaction
  primitives to avoid concurrent write clobbering. (#3023)

Removed
-------

- Removed the unused ``ots:migration_needed:db_0`` Redis write on application
  boot, saving one round-trip per startup. (#3027)

Fixed
-----

- **Homepage configuration backfill**: Added a migration to preserve public
  homepage settings for existing custom domains under the new split
  configuration architecture. (#3023)
- **Cascading domain deletion**: ``CustomDomain#destroy!`` now reliably cleans up
  companion configuration records, preventing orphan Redis keys. (#3023)
- **Organization lookup restoration**: Restored organization email indexes
  destroyed by automated cleanup logic during membership activation. (#3023)
- **Thread-safe unique index validation**: Refactored domain claiming to run
  unique-index validations outside of MULTI blocks, resolving intermittent
  concurrent verification failures. (#3025)

.. _changelog-v0.24.2:

v0.24.2 — 2026-03-14
====================

Added
-----

- ``Middleware::LocaleFallback`` Rack middleware applies the ``fallback_locale``
  config chains after Otto's initial locale detection, walking the configured
  chain to find the best available match (e.g. ``fr-CA`` falls back to
  ``fr_FR`` when ``fr_CA`` is unavailable).

Changed
-------

- Promoted 10 locales from ``incomplete`` to fully supported: ar, ca_ES, cs, he,
  hu, pt_PT, ru, sl_SI, vi, zh. Added eo (Esperanto). All 30 locales are at
  92-94% translation coverage; the ``incomplete`` config section is removed.

- Expanded ``fallback_locale`` chains to cover all regional variants (ca, da,
  el, mi, pt-BR, pt-PT, sl, sv) so related locales degrade gracefully.

Fixed
-----

- Browser language detection now works for regional locale variants (e.g.
  ``it-IT``, ``fr-FR``, ``pt-BR``). Previously 13 of 19 production locales
  failed Accept-Language auto-detection, showing English instead. (#2668)

- Frontend ``navigator.language`` is now read during store initialization, so
  anonymous users on public pages (e.g. secret reveal) get the correct language
  instead of always falling back to English. (#2668)

AI Assistance
-------------

- Claude assisted with the locale fallback middleware, the ``navigator.language``
  store wiring, and test coverage for server and frontend locale detection.

.. _changelog-v0.24.1:

v0.24.1 — 2026-03-12
====================

Added
-----

- V1 API validation tooling in ``scripts/api-validation/bin/``:
  ``v1-capture.sh`` records request/response pairs from a running instance;
  ``v1-diff.sh`` compares two captures and flags field, type, status code, and
  header changes. (#2615)

Changed
-------

- V1 API is now frozen. No new fields or endpoints; new functionality targets
  V2/V3. All V1 responses emit v0.23.x field names and state values for backward
  compatibility. (#2615, PR #2626)

Fixed
-----

- V1 receipt and secret decryption for Familia v2 compatibility (P0).
- ``NoMethodError`` in ``show_receipt_recent`` — now returns Receipt objects (P0).
- Field name mapping (e.g. ``identifier`` → ``metadata_key``,
  ``secret_identifier`` → ``secret_key``, ``receipt_ttl`` → ``metadata_ttl``,
  ``secret_value`` → ``value``) and state value translation (``previewed`` →
  ``viewed``, ``revealed`` → ``received``, ``shared`` → ``new``) restored to the
  v0.23.x contract.
- ``custid`` emits customer email address (not internal UUID); ``share_domain``
  returns empty string instead of null; ``received`` timestamp falls back to
  ``revealed`` when empty.

AI Assistance
-------------

- Claude assisted with debugging V1 compatibility regressions, the
  ``receipt_hsh`` field mapping, and validation tooling and test coverage.

.. _changelog-v0.24.0:

v0.24.0 — 2026-03-05
====================

Added
-----

- UUIDv7 refinements for SecureRandom, String, and Time.

- New unified session and authentication architecture: a standard
  ``Onetime::Session`` store, an authentication adapter supporting both
  Redis-backed auth and Rodauth, identity-resolution middleware across all
  applications (API v1/v2, Web Core), dual auth-mode detection, and Otto↔Rodauth
  identity bridging (external IDs, ``RodauthUser``, account-closure cleanup).
  Includes a YAML-based auth configuration system, migration/rollback tooling,
  and a migration guide. (#1619, #1673)

- CSRF protection via shrimp tokens integrated with Rack sessions.

- Git JSON merge driver (with ``.gitattributes`` wiring) for automatic 3-way
  merging of ``src/locales/**/*.json`` conflicts.

- Secret reveal notifications: users can opt in to email when their secrets are
  viewed, via a new Notifications settings page
  (``/account/settings/profile/notifications``) and a ``notify_on_reveal``
  Customer field.

- Dashboard experience variants adapting to user capabilities and team count,
  with a no-teams onboarding flow. Self-hosted installs get full capabilities
  when billing is disabled.

- Development process manager (``bin/dev`` + ``Procfile.dev``) for single-command
  startup of backend (Puma, port 7143), Vite frontend, and worker via Overmind,
  plus an ``install-dev.sh`` setup script for multi-worktree development.

- New ``DlqEmailConsumerJob`` replays auth-critical emails from the dead-letter
  queue on a 5-minute cycle (raw Rodauth emails always; templated auth emails
  only while their key is valid; non-auth emails discarded). Enabled by default;
  set ``JOBS_DLQ_CONSUMER_ENABLED=false`` to disable. (PR #2530)

Changed
-------

- Migrated all models to the new SafeDump DSL (``safe_dump_field``), replacing
  the ``@safe_dump_fields`` class-instance-variable pattern.

- Session management unified on Redis-backed ``Onetime::Session`` (via
  ``env['onetime.session']``) instead of custom or Roda sessions, with unified
  cookie naming (``onetime.session``, ``onetime.remembers``) and Otto-integrated
  validation. Colonel stats no longer count sessions (handled by middleware).

- Refactored API v2 authentication strategies to Otto 1.5+ class-based
  architecture and adopted Otto ``RequestContext`` for request state management.
  (#1619)

- Customer migration now uses deterministic external IDs derived from the UUID
  hash instead of random values.

- Publisher supports configurable RabbitMQ fallback strategies — ``:async_thread``
  (default, non-blocking), ``:sync``, ``:raise``, or ``:none`` — replacing the
  previous blocking 3-second retry. Critical auth flows use ``:sync``;
  non-critical paths use ``:none``. (PR #2064)

- **Frontend architecture**: restructured the Vue app from flat
  ``views/``/``components/`` to a domain-driven ``apps/`` structure with five
  modes: Secret, Workspace, Session, Kernel, and Billing. (PR #2114)

- Replaced WindowService with a Pinia ``bootstrapStore`` as the single source of
  truth for server-injected state (window var renamed ``__ONETIME_STATE__`` →
  ``__BOOTSTRAP_ME__``, deleted after consumption).

- Renamed TeamDashboard to TeamView; standardized API params from symbol to
  string keys; team updates use PUT instead of PATCH.

- DLQ message TTL is now managed via a RabbitMQ policy (``dlq-ttl``) rather than
  immutable queue arguments (which caused ``PRECONDITION_FAILED`` on TTL
  changes). ``bin/ots queue init`` applies the policy; ``bin/ots queue status``
  reports it. (PR #2529)

- Simplified ``.env.example`` (removed shell export directives, added explicit
  ``NODE_ENV=production``) and added an ``.env.sh`` symlink convention.

**Upgrading existing installs** with DLQ queues declared before this release:
stop workers, then ``bin/ots queue reset --force`` (this destroys DLQ messages —
drain them first if they must be preserved) and ``bin/ots queue init`` to
recreate infrastructure and apply the ``dlq-ttl`` policy.

Removed
-------

- Removed the ``V2::Session`` model, ``SessionMessages`` mixin,
  ``ClearSessionMessages`` middleware, and other deprecated custom
  session-management code (superseded by ``Rack::Session``).

- Removed the NewRelic dependency from the auth service Gemfile (moved to
  application-level configuration).

Fixed
-----

- Fixed a ``NameError`` in ``ShowSecretStatus`` (``current_expiration`` →
  ``@realttl``) and syntax errors (double-dot ``to_s``) in the Team and
  Organization models.

- Auth service now loads Vite assets correctly in both development and
  production, eliminating the style flash and Vue init errors; added critical
  CSS to prevent flash of unstyled content and removed a duplicate
  ``window.__ONETIME_STATE__`` initialization.

- Various session/auth fixes: Redis session key reference in identity-resolution
  middleware (#1679), a missing ``Singleton`` require, configurable session-expiry
  values, and correct auth-mode detection.

Documentation
-------------

- Added ``AUTHENTICATION_MIGRATION.md`` (migration procedures, rollback,
  troubleshooting) and an authentication configuration reference. Added Git JSON
  merge driver setup instructions to the README.

AI Assistance
-------------

- Claude assisted with the SafeDump DSL migration, the Otto/Rodauth session and
  authentication refactor, the frontend ``apps/`` migration, the RabbitMQ
  fallback API, secret-reveal notifications, dashboard variants, and the
  ``DlqEmailConsumerJob``.
