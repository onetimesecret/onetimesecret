CHANGELOG
=========

All notable changes to Onetime Secret are documented here.

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__, and
this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

.. _changelog-0.26.0:

0.26.0 — 2026-07-20
======================

Added
-----

- Mobile/social favicon "variety pack": the HTML head now emits an SVG favicon,
  Apple touch icon, PWA web manifest + icons, Safari pinned-tab mask icon, and
  Open Graph / Twitter ``og:image``. Per-custom-domain favicons continue to
  take precedence (#3048, #3049).

- The favicon generator (``scripts/branding/``) is now a reusable, fully
  parameterized tool. The glyph (``MARK_PATH`` + ``MARK_NATIVE_WIDTH`` /
  ``MARK_NATIVE_HEIGHT``), palette (``MARK_PRIMARY_COLOR``,
  ``MARK_BACKGROUND_COLOR``, ``MARK_OG_GRADIENT_DARK``), manifest name
  (``MARK_PRODUCT_NAME`` / ``MARK_SHORT_NAME``), glyph sizing (``MARK_COVERAGE``
  and friends), and an optional license credit (``MARK_ATTRIBUTION``, embedded as
  an SVG comment) are all overridable without editing the source. Named override
  bundles live as presets in ``scripts/branding/presets/`` and are selected with
  ``--preset <name>`` (shell-portable) or the ``MARK_PRESET`` env var. Preset
  names are validated against path traversal and unknown keys are reported, and a
  dependency-free test suite (``pnpm run gen:favicons:test``) covers the pure
  logic.

- Optional Onetime Secret company-brand favicon pack, ``pnpm run
  gen:favicons:maruhi``, ships as the first preset: it renders the "maruhi" mark
  (circled 秘 "secret" glyph) in the current logo's orange/white palette
  (``OnetimeSecretIcon.vue`` / onetime-logo-v3) through the shared generator, no
  separate code path. Writes the deployable pack to ``public/branding/maruhi/``
  and a reviewable source copy to ``src/assets/branding/maruhi/``, leaving the
  brand-neutral defaults in ``public/web/`` untouched (#3048, #3049).

- New ``BRAND_LOGO_ALT`` / ``brand.logo_alt`` setting for operator-supplied
  brand-logo alt text; when unset, alt text falls back to an i18n string
  derived from the product name. (#3612)

- Custom domains can now present the Incoming Secrets form as their public
  homepage. The Domain detail screen replaces the Homepage Secrets on/off
  toggle with a three-way Homepage selector — private landing page, secret
  creation form, or incoming secrets form — stored backend-side as a new
  ``secrets_mode`` field (``create`` | ``incoming``) on the per-domain
  HomepageConfig. The incoming option can only be selected once incoming
  secrets is enabled with at least one recipient (enforced in the UI and by
  ``PUT /homepage-config``), and if incoming later drifts unready — recipients
  removed, incoming disabled, feature flag off, or entitlement lapsed — the
  public homepage fails closed to the private landing page rather than falling
  open to the create form. Anonymous secret creation via the API is likewise
  refused on incoming-mode homepages. Existing domains are unaffected
  (missing ``secrets_mode`` reads as ``create``); the optional
  ``20260703_02_backfill_homepage_secrets_mode`` migration persists the
  explicit default onto legacy records.

- Access telemetry on the receipt: every fetch of a secret's link or status
  is recorded as an append-only event on the receipt's access timeline
  (capped, expires with the receipt). The receipt endpoints now surface the
  derived aggregates in their details payload — ``view_count`` (previously
  always ``null``) plus new ``first_access`` and ``last_access`` epoch
  timestamps — so creators can see whether and when a link was accessed,
  even after the secret itself is consumed. (#3633)

- Organization audit trail: secret activity for receipts created in an
  organization's context — creation, link/status fetches, reveal, burn,
  expiry — is now recorded to a per-organization audit stream and exposed
  via ``GET /api/organizations/:extid/audit-events`` (paginated, newest
  first). Access requires the ``audit_logs`` entitlement, which the
  role/plan intersection grants to admins and owners on qualifying plans;
  this makes the previously catalog-only entitlement functional. Events
  carry receipt/secret shortids only, never full identifiers. Creator
  self-access is recorded distinctly (``creator_status_get`` for a status
  check, ``previewed`` for opening their own secret link), the receipt-page
  view is recorded as ``receipt_viewed`` (unambiguous, unlike the UI word
  "preview"), and a
  single hammered link cannot flood the org trail — each receipt
  contributes at most its own per-receipt cap of fetch events. (#3633)

Changed
-------

- Updated the favicon/icon/social defaults to be brand-neutral. Regenerate
  with ``pnpm gen:favicons``.

- The custom email sender form now pre-fills ``no-reply@<domain>`` and the
  organization name as defaults for domains without a saved configuration, so
  operators can enable it without choosing an address first.

- The custom email sender's address-field placeholder is now localizable.

- The neutral product name shown on unbranded / private-label installs is now
  "Secure Links" instead of "My App", across the UI and the PWA manifest.
  Installs that configure ``BRAND_PRODUCT_NAME`` or per-domain branding are
  unaffected.

- Viewing a secret link no longer resets the secret's expiration. Previously
  each view extended the time-to-live back to the full lifespan, so a
  repeatedly-viewed link could outlive its intended expiry; secrets now always
  expire on their original schedule regardless of how often the link is viewed.

- The ``brand:`` config block is now the single authority for brand identity:
  one documented path (``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``,
  ``BRAND_LOGO_ALT``) brands the masthead, outbound emails, page titles, and
  MFA labels. ``BRAND_LOGO_URL`` now drives the masthead operator logo too
  (previously it was email-only); emails only emit absolute http(s) logo URLs,
  degrading to a text-only header otherwise. (#3612)
- The header config is reduced to masthead layout knobs under
  ``site.interface.ui.header.logo`` — ``href`` (``LOGO_LINK``), ``show_name``
  (``LOGO_SHOW_NAME``), and ``prominent`` (``LOGO_PROMINENT``); the env vars
  are unchanged. ``show_name`` unset now means "show the wordmark unless a
  custom brand logo is configured". (#3612)
- Unconfigured installs now present a fully neutral identity — the "Secure
  Links" name and keyhole mark in the masthead, emails, and page titles —
  instead of the old "One-Time Secret" defaults. (#3612)
- TOTP/MFA authenticator entries now use the configured product name as the
  issuer label when ``BRAND_TOTP_ISSUER`` is unset, so renamed installs brand
  new MFA enrollments too. (#3612)

- Custom-domain screens no longer show Approximated-based DNS status (the
  "Inactive"/"DNS incorrect" badges and verification flow) on installs that
  don't use the ``approximated`` validation strategy. Self-hosted and custom
  installs manage their own DNS and TLS, so those badges — which only ever
  populate from Approximated's per-domain check — previously made every domain
  look permanently invalid. Adding a domain on such installs now opens a simple
  DNS-setup screen showing the CNAME record to point at the canonical domain,
  instead of the Approximated verification screen.

- Secret-link and incoming-secret emails render the secret's custom domain in
  the shared layout's header wordmark and footer link. Account and system
  emails, and install-level links inside email bodies, still use the
  canonical host.

- Custom-domain homepages no longer show the **Create Account** and **Sign In**
  nav links by default. The per-domain ``signup_enabled`` / ``signin_enabled``
  toggles on ``CustomDomain::HomepageConfig`` now default to *off*, matching the
  conservative default of the sibling ``SigninConfig`` / ``SignupConfig``
  models, so recipients and employees arriving via a shared secret link no
  longer see account chrome that isn't meant for them. Operators re-enable the
  links per domain via ``PUT /homepage-config`` (domain homepage settings). The
  authentication kill switch (``resolve_signin_enabled`` /
  ``resolve_signup_enabled`` and the serializer's ``effective_*`` gates) is
  unchanged — this only narrows what is displayed, never widens capability.
  (#3618)

- **Action Required**: existing custom domains have these flags persisted as
  ``true`` (written by ``CustomDomain.create!`` and the #3023 backfill), so a
  code-only default change cannot reach them. A data migration resets the stored
  values to ``false``; run it during deployment::

      bin/ots migrate --run 20260703_01_disable_homepage_auth_links

  The migration is idempotent (already-off records are skipped) and preserves
  each domain's homepage ``enabled`` (public secret form) setting. (#3618)

- ``GET /api/incoming/config`` on custom domains now reports
  ``enabled: false`` when the domain's incoming config has no recipients,
  so the /incoming page shows its disabled state instead of an
  unsubmittable form with an empty recipient dropdown.

- Reading a secret no longer changes it: ``GET /secret/:identifier`` and
  ``GET /secret/:identifier/status`` (v2 and v3) previously advanced the
  secret's lifecycle state from ``new`` to ``previewed`` as a side effect of
  the read, violating HTTP safe-method semantics and polluting the
  creator-facing "was my secret seen?" signal with mechanical fetches. The
  lifecycle state now only advances on a genuine reveal or burn. (#3633)

- ``previewed`` is retired as a receipt lifecycle *state*: no request path
  advances a receipt to ``previewed`` anymore. New receipts move
  ``new -> revealed/burned/expired/orphaned`` only. The creator's own
  secret-link open is now surfaced from the append-only access timeline
  (``view_count`` / ``first_access``) rather than a mutated state field,
  and is recorded in the org audit trail as ``previewed`` (was
  ``creator_secret_get``). Read-side ``state?(:previewed)`` checks and the
  ``previewed`` field are retained for backward compatibility with data
  written before this change. (#3633)

- The ``is_previewed`` receipt attribute now means "the secret link has been
  accessed at least once" (derived from the access timeline), not "state ==
  previewed". This keeps every consumer working after the state was retired:
  the receipt page's post-creation banner and the recent-secrets dashboard
  status now key off telemetry instead of a mutated field, with no
  client-side change. Legacy receipts still in a ``previewed``/``viewed``
  state continue to report ``true``. (#3633)

- The legacy v1 secret and receipt read endpoints (and the v1
  ``generate``/``show_receipt`` controllers) no longer advance state on a
  GET, matching v2. Downstream guards (``viewable?``, ``burned!``,
  ``win_reveal_claim!``) already accept ``new``, so no behavior depends on
  the removed transitions. (#3633)

- The V1 API receipt endpoint no longer reveals a concealed (user-supplied)
  secret's plaintext to the creator, aligning V1 with the V2/V3 behavior:
  only generated values are shown on the receipt, only on first view, and
  only within ``site.secret_options.generated_value_display_ttl`` of
  creation. Reading concealed plaintext back from the receipt sidestepped
  the at-most-once rule that V2/V3 deliberately enforce; this corrects a
  long-standing inconsistency between the API versions. The creator already
  holds the plaintext they submitted, so nothing accessible is lost.

Deprecated
----------

- ``SITE_NAME``, ``LOGO_URL``, and ``LOGO_ALT`` (the
  ``site.interface.ui.header.branding`` path) are deprecated in favor of
  ``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``, and ``BRAND_LOGO_ALT``. Legacy
  values are still honored as fallbacks; boot logs a warning naming the
  replacement but never refuses to start, even under
  ``DEPRECATED_CONFIG_MODE=strict``. (#3612)

Removed
-------

- The legacy v1 API is now strictly JSON-only. Its hand-rolled
  Content-Security-Policy, the per-request nonce it generated, and its unused
  HTML-response capability (the ``publically`` wrapper and ``carefully``'s
  ``text/html`` default plus web-redirect handling) are all removed. v1 renders
  no HTML and is never executed by a browser; CSP is owned solely by Otto's
  response layer (the single policy source).

- The 32 tuning/toggle ``JOBS_*`` environment variables (per-job ``enabled``,
  ``interval``/``check_interval``, ``batch_size``, ``cron``, ``*_hours``,
  ``sample_size``, ``rate_limit``, and ``auto_repair`` across the domain-refresh,
  expiration-warnings, phantom-cleanup, data-audit, participation-gc,
  index-rebuild, instances-rebuild, housekeeping, plan-cache-refresh,
  catalog-retry, dlq-consumer, and maintenance jobs) no longer take effect;
  their defaults are now inlined directly in
  ``etc/defaults/config.defaults.yaml``. Nothing outside that YAML ever read
  these vars, so no runtime behaviour changes for a default deployment. To
  enable or tune one of these jobs, set the value in the ``jobs:`` block of your
  ``etc/config.yaml`` override file (which deep-merges over the shipped
  defaults) instead of exporting an env var. The three genuine deploy-time
  switches — ``JOBS_ENABLED``, ``JOBS_FALLBACK_SYNC``, and
  ``JOBS_SCHEDULER_ENABLED`` — are unchanged and remain env-overridable.
  (#3775)

Fixed
-----

- The global authentication kill switch (``AUTH_ENABLED`` / ``AUTH_SIGNIN`` / ``AUTH_SIGNUP``) is now authoritative over per-domain sign-in and sign-up configuration. The runtime gates ``Core::Controllers::Base#signin_enabled?`` and ``#signup_enabled?`` previously used replace semantics, so an enabled per-domain ``SigninConfig``/``SignupConfig`` could re-enable sign-in or sign-up on a custom domain even while the operator had disabled it globally. Both gates and the ``ConfigSerializer`` display gate now resolve through shared ``SigninConfig.resolve_signin_enabled`` / ``SignupConfig.resolve_signup_enabled`` helpers that AND the per-domain override with the global capability — a domain config may only narrow, never widen, the install-level setting. (#3453)

- Schema validation failures now name the field that failed — in the log message
  and a searchable ``schemaField`` Sentry tag (paths and codes only, never
  values) — instead of a generic "Schema validation failed". (#3424)

- A transient or schema failure on the secret reveal page is no longer shown as
  "this secret has been viewed or expired"; only a genuine 404 shows that, while
  load errors get a distinct, retryable message. (#3424)

- Receipts no longer fail to load when a numeric or timestamp field is
  string-typed at rest: ``ShowReceipt`` coerces ``expiration_in_seconds`` and the
  ``previewed``/``revealed``/``burned``/``shared`` timestamps at the boundary, and
  ``expiration`` may now be null for a consumed or expired secret. (#3424)

- Czech and Dutch UI copy that had drifted out of each locale's locked
  informal register is corrected: Czech now uses the informal ``ty``
  possessives/pronouns throughout (13 strings), and Dutch now uses informal
  ``je``/``jouw`` across all flagged copy — product UI, plus the
  legal/marketing strings that had used formal ``u``/``uw`` (34 strings total).
  Surfaced by the resolver-engine register gate; both locales now scan clean.
  (#3530)

- A ``fallback: :sync`` email delivery failure (for example, an unreachable SMTP
  host while background jobs are disabled) no longer returns HTTP 500 after the
  underlying record was already persisted. Synchronous fallback delivery now
  honours its documented contract — it blocks and delivers, logging/reporting a
  failure instead of raising — so organization invitations, email-change
  requests, password resets, and Rodauth auth emails degrade gracefully and stay
  resendable. Use ``fallback: :raise`` when a caller must surface the failure.
  (#3486)

- The default logo and the unbranded disabled-homepage fallback now use the
  neutral keyhole mark instead of OneTimeSecret's Japanese "maruhi" (秘)
  branding, so private-label and custom-domain deployments no longer leak OTS
  branding. (#3048, #3049)

- Replaced several hardcoded OneTimeSecret brand colors (the disabled-homepage
  accent dot, decorative broadcast/globule gradients, and a button shadow)
  with brand design tokens, so they follow per-domain branding instead of
  always rendering OTS colors.

- Unbranded domains now default to light button text instead of dark, matching
  the neutral brand contract. Clearing the primary color in the branding
  live-preview also resets the button-text contrast, instead of keeping the
  previous color's setting.

- Branded logo accessibility: the custom-domain masthead logo now has a
  meaningful ``alt`` (the brand name) instead of an empty one, and the default
  logo no longer announces its label twice to screen readers.

- The custom-sender API no longer rejects a blank ``from_address`` with "From
  address is required"; it now defaults to ``noreply@<domain>`` first, so an
  operator can enable the sender without hand-typing an address, matching the
  frontend default.

- The disabled-homepage page no longer renders a stray rectangular surface
  behind its centered content in light mode. A background tint applied to a
  non-full-height wrapper left a visible boxed seam above a plain gap; it's
  now removed, matching dark mode's already-consistent look.

- A password-reset request for a pending (unverified) account no longer returns
  a 500. ``send_verification_email`` bound the verification secret to the
  request-context customer, which is nil in the unauthenticated reset flow; it
  now accepts the recipient explicitly (defaulting to ``cust``), so the resend
  succeeds and the request returns the same generic success as every other case
  — keeping the password-reset response uniform across registered, pending and
  unregistered addresses. (#3486)

- Custom domains with no uploaded logo no longer show the platform's site name
  beside the fallback logo, and page titles and social-share meta tags fall back
  to the configured brand name instead of a hardcoded "Onetime Secret". Both
  surfaces now resolve brand identity through the shared resolver, so the
  neutral-safe fallback for private-label installs is applied consistently.
  (#3566)

- ``scripts/branding/mark.mjs``'s ``MARK_PATH`` glyph override silently
  mis-scaled and mis-centered any glyph whose native size wasn't the keyhole's
  512x1024. The native bounds are now configurable via ``MARK_NATIVE_WIDTH`` /
  ``MARK_NATIVE_HEIGHT``, so custom-glyph packs render correctly.

- The Content-Security-Policy header is now emitted on web (HTML) responses by
  default. It was previously gated behind ``CSP_ENABLED=true`` and so was not
  output as intended. The policy is generated by Otto (the single policy
  source) using the per-request nonce. Set ``CSP_ENABLED=false`` to opt out.

- The operator/install logo no longer leaks onto tenant custom domains: they
  show their own uploaded logo or the neutral mark, matching the existing
  wordmark guard. (#3612)

- Incoming secrets (``/incoming``) submitted on a custom domain are now bound
  to that domain: the notification email links to the secret on the custom
  domain and is delivered via that domain's sender config, matching the
  authenticated share flow.

- ``Receipt#expired!`` had no state guard, so every later view of an
  already-expired receipt re-ran the transition (redundant writes and
  duplicate log entries — and duplicate audit events once the trail
  existed). The transition now only fires from a live (new/previewed)
  receipt, matching its sibling transitions. (#3633)

- Viewing a secret's receipt/metadata page no longer mutates the secret's
  lifecycle state. The receipt-page GET previously flipped the receipt to
  ``previewed`` as a side effect, conflating "the creator looked at their
  own receipt" with "the secret link was opened". Loading the receipt page
  now records a one-time ``receipt_viewed`` audit event (bounded per receipt
  by a new ``receipt_viewed_at`` observability field, so a bookmarked or
  monitored receipt page cannot flood the org's capped audit trail);
  ``previewed`` is reserved for the distinct, auditable event of the creator
  opening their own secret *link* (recorded on the access timeline). This
  completes the #3633 GET-safety work, which had left the receipt-page
  transition (and the legacy v1 GET transitions) in place. (#3633)

- A generated secret's plaintext is now shown to its creator on the receipt
  page *exactly once* ("one time"). Retiring the ``previewed`` state mutation
  had left the value re-displayable on every reload within the display window
  (v2) or unbounded (v1). Both paths now claim the display atomically via a
  new ``secret_value_shown_at`` field (Redis ``HSETNX``), so a repeated or
  concurrent load never re-reveals the value. The claim is taken at display
  time: an at-most-once semantic, matching the old state gate — a lost
  response forfeits the reveal rather than risking a second one. The display
  window (``generated_value_display_ttl``) now bounds only *when* the single
  reveal may occur, not how many times. (#3633)

- The one-time ``receipt_viewed`` audit event is now claimed atomically as
  well, so simultaneous first-loads of a receipt record exactly one event
  instead of racing to record two. (#3633)

- Checkout session creation now sends a fresh UUID idempotency key on every
  attempt instead of a deterministic time-bucketed key (daily in live mode,
  per-minute in test mode). Customers who retried checkout within the same
  window previously received Stripe's cached — possibly already-completed —
  session ("You're all done here"), and same-window requests with changed
  session parameters raised ``Stripe::IdempotencyError``. Duplicate
  *completions* remain deduplicated by the ``checkout.session.completed``
  webhook handler; mutation calls such as plan changes keep their
  deterministic 5-minute-window keys so retries still collapse to one applied
  change. See ``apps/web/billing/docs/adr-checkout-idempotency-keys.md``.
  (#2605)

- Checkout now blocks an organization that already owns a genuinely active,
  non-canceling subscription from starting a second checkout session (on
  both the API and plan-redirect paths), and the
  ``checkout.session.completed`` handler detects and loudly logs a completed
  checkout that would overwrite a *different*, still-active subscription.
  This closes a duplicate-subscription hazard — a double charge plus an
  orphaned, still-charging Stripe subscription — that could otherwise occur
  on rapid retries or multiple open tabs now that session creation uses
  per-attempt UUID idempotency keys. Currency-migration and
  resubscribe-after-cancel flows, where the prior subscription is winding
  down, remain exempt. (#2605)

- The notifications worker's prefetch default in
  ``etc/defaults/config.defaults.yaml`` now reads ``5`` instead of ``10``,
  matching the value the worker actually runs with. ``NotificationWorker``
  declares its queue with ``ENV.fetch('NOTIFICATION_WORKER_PREFETCH', 5)``, so
  when the env var is unset the worker has always prefetched 5 messages while
  the config file misreported 10. This aligns the documented default with
  runtime and with the sibling ``billing`` worker (also 5); the high-throughput
  ``email`` worker keeps its 10. No runtime behaviour changes for a default
  deployment. Surfaced during #3777 review.
  (#3777)

Security
--------

- Password-reset requests no longer reveal whether an email address has an
  account (CWE-204). ``ResetPasswordRequest`` previously returned a generic
  success for a registered address but raised "Invalid email address" for an
  unregistered one, which allowed account enumeration. Validation now checks
  only the email format; a well-formed but unregistered address gets the same
  generic success response, with no reset secret created and no email sent —
  matching the existing ``CreateAccount`` behaviour. (#3486)

- The hardened config and logger YAML loaders now permit ``Date`` and ``Time`` in addition to ``Symbol`` (the recommendation from the original security review). Previously the loaders permitted only ``Symbol``, so an unquoted date or time in a deployment's ``config`` or ``logging`` YAML (e.g. ``expires: 2026-01-02``) raised ``Psych::DisallowedClass`` and prevented boot until every such value was quoted — a latent breaking change. Unquoted dates/times now load as ``Date``/``Time`` instances again, while arbitrary Ruby objects (``!ruby/object``) remain rejected. The runtime loader, the ``deep_clone`` round-trip, and the config validator keep their permitted-class lists symmetric, so a config that validates also boots. (#3498)

- Fixed a double-reveal race on burn-after-reading secrets (CWE-362). Two
  concurrent requests to the same secret link could both pass the viewability
  check, decrypt, and return the plaintext before either destroyed the record,
  so a "view once" secret could be disclosed to more than one recipient —
  defeating the core product promise. Revealing or burning a secret now claims
  it with an atomic compare-and-set in the datastore, so exactly one caller may
  consume it; any request that loses the race receives no secret value.

- A burn request that loses the race no longer counts toward burn metrics nor
  reports success to the caller.

- Closed a related re-exposure window. Recording that a secret link had been
  viewed wrote the secret's state unconditionally, which could momentarily
  revert a just-revealed secret back to a viewable state while its ciphertext
  still existed, and could recreate a secret that a concurrent reveal or burn
  had already destroyed. The state transition is now atomic and can neither
  revert a consumed secret nor recreate a destroyed one.

- Federated subscription benefits are no longer claimed before an account's
  email is verified. Previously a pending cross-region subscription (matched
  by email hash) was claimed during standard email/password signup, before
  the verification email was even sent — letting someone who knew a
  subscriber's email register that email in another region and claim the
  subscriber's benefit. The claim is now deferred to ``after_verify_account``
  when email verification is enabled, and an unverified signup no longer
  computes an indexed email hash until it verifies. SSO (identity-provider
  verified), invite, and post-payment flows are unaffected.

- Federated subscription claims made without email verification are now
  surfaced by a loud, structured security-audit log. When a deployment turns
  email verification off (``verify_account`` disabled), the standard signup
  path still claims a matching cross-region subscription immediately because
  there is no verification step to defer to — an unavoidable residual of that
  configuration. ``CreateDefaultWorkspace`` now detects that risky combination
  (federation active *and* verification disabled) at claim time and logs the
  org, email-hash prefix, and plan, noting the benefit was applied with no
  proof of email ownership, so operators can spot abuse. Happy-path behavior is
  unchanged; verified customers and verify-enabled deployments never trip it.
  The residual is documented precisely in the workspace-creation operation and
  the account hooks, and a new full-stack integration spec drives the real
  Rodauth signup hook to prove the deferred (verify-enabled) and immediate
  (verify-disabled + audit) branches end-to-end.

.. _changelog-v0.25.11:

v0.25.11 — 2026-06-20
=====================

Fixed
-----

- Secrets and Receipts now guarantee a non-null integer ``lifespan``/TTL end-to-end, closing the null half of #3424. ``Receipt.spawn_pair`` — the single creation choke point — coerces ``lifespan`` to an Integer, which both stores the correct type (Familia v2 is type-preserving, so a ``String`` would persist as a ``String``) and fixes a latent bug where ``lifespan * 2`` string-multiplied the receipt's expiration. Config normalization now also coerces the confirmed leak path ``features.incoming.default_ttl`` (set from an env var via ERB, so a set ``INCOMING_DEFAULT_TTL`` yielded a ``String``) and hardens ``site.secret_options.default_ttl`` against any non-Integer, not just ``String``. The ``safe_dump`` lambdas emit a plain integer with no ``nil``/``-1`` sentinel, and the V3 ``secret``/``receipt`` contracts keep ``secret_ttl``/``receipt_ttl``/``lifespan`` as strict, non-nullable ``z.number()`` — the read-time enforcement of that invariant. An earlier patch widened those fields to ``z.number().nullable()``; it was reverted because a real record can never have an ambiguous expiration. (#3424, #3299)

- **SSO sign-in no longer freezes when the IdP returns no usable email.** When an identity provider (Entra ID, OIDC, …) authenticates a user but supplies no usable email claim, the OmniAuth callback redirects to ``/signin?auth_error=invalid_email`` and the sign-in page now reliably renders a localized error instead of a blank/"frozen" loading screen. The frontend now shows a message for *any* ``auth_error`` code — unrecognized codes (e.g. from a backend newer than the deployed bundle) fall back to a generic SSO-failure message rather than rendering nothing — and the backend callback guard now also rejects an empty local part (``@example.com``) so it can no longer fall through to account creation and 500. This is a stopgap for the frozen-screen symptom; supplying a stable identifier fallback (UPN/``oid``) for emailless SSO users is tracked separately. (#3478)

.. _changelog-v0.25.10:

v0.25.10 — 2026-06-13
=====================

Added
-----

- ``scripts/diagnostics/detect_string_typed_numerics.rb``, a read-only scan that finds Secret/Receipt records whose numeric fields are stored as JSON strings at rest (the corruption behind #3424, distinct from the non-JSON bytes that ``check_raw_email_fields.rb`` finds for #3016). The ``safe_dump`` cast keeps the API correct, but the bytes stay corrupt; this locates them and reports a per-record signature to help trace the writer. (#3424)

- One-click SSO on the disabled-homepage variants (``minimal`` and ``v1``).
  When SSO is the sole login method and a single provider is configured, the
  homepage shows a direct SSO sign-in button instead of a ``/signin`` link,
  mirroring the activation logic of the auth-method selector (global
  ``restrict_to: sso`` or a custom domain with ``enforce_sso_only``). (#3433)

- ``scripts/ip_privacy_trusted_proxy_repro.rb``, a standalone diagnostic that
  models the chained ``IPPrivacyMiddleware`` instances and prints the broken
  vs. fixed behaviour, kept for the trusted-proxy harmonization follow-up.
  (#3427)

Changed
-------

- The disabled-homepage ``legacy`` variant is renamed to ``closed`` and is now
  the default. It remains a quiet, no-CTA placeholder; self-hosters who pinned
  ``minimal`` or relied on the ``legacy`` name should update their disabled
  homepage configuration. (#3433)

- Corrected the MFA recovery-code generation comment, which inaccurately described the codes as 8-character / ``36^8``. ``new_recovery_code`` emits a CSPRNG-backed 64-bit base36 token (~13 chars, ~1.8e19 possibilities); the comment now documents the real format and entropy. No change to the generated codes. (#3455)

Fixed
-----

- Secret and Receipt API responses now coerce their numeric fields to numbers at the ``safe_dump`` serialization boundary: TTL/lifespan fields (``lifespan``, ``secret_ttl``, ``metadata_ttl``, ``receipt_ttl``) cast to integers, and the ``created``/``updated`` timestamps cast to floats so their sub-second precision (used as sorted-set scores) is preserved. Familia v2 storage is type-preserving, so a record whose numeric fields were ever written as strings (unconverted params, console writes, raw ``HSET``) hydrated them as strings and failed the strict ``z.number()`` V3 schema — recipients saw "That information is no longer available" for secrets that were never consumed, with the sender's dashboard stuck on "Previewed". The cast is a no-op for healthy records and neutralizes affected ones; it emits a plain integer with no ``null``/``-1`` sentinel, since a real record always has a lifespan (see #3299 for the write-time guarantee). (#3424, #3268)

- MFA enrollment QR codes now encode the secret the server actually
  validates. With HMAC mode enabled the frontend was reconstructing the
  ``otpauth://`` URI from ``otp_raw_secret`` (the setup-handshake key) instead
  of ``otp_setup`` (the HMAC'd key the authenticator must use), so scanned
  codes never matched and setup could not complete. The backend now emits
  Rodauth's authoritative ``provisioning_uri`` and the frontend renders it
  directly without reconstruction. (#3431)

- Behind a trusted proxy, the IP-privacy middleware now masks the real client
  IP instead of the proxy's. The middleware was mounted first in the common
  stack with no security config, so it resolved ``REMOTE_ADDR`` (ignoring
  ``X-Forwarded-For``) and overwrote the forwarded headers with a masked proxy
  address before any later strategy could read the client IP — the
  ``site.network.trusted_proxy`` setting from #3116 ran too late to help. The
  middleware stack now passes it an Otto security config that trusts the
  private proxy ranges (RFC1918, loopback, link-local, IPv6 ULA/loopback) when
  ``site.network.trusted_proxy.enabled`` is true. Direct-connection
  deployments are unaffected; the stored IP is still masked to a /24, just the
  correct one. Public-egress CDN ranges still need CIDR matching, which Otto's
  prefix-based trusted-proxy list does not do. (#3427)

- The burn endpoints (v1 and v2) now honour ``continue=false``. Both parsed
  the flag into a proper boolean in ``process_params`` but then computed
  ``greenlighted`` from the raw ``params['continue']`` instead. Because every
  non-empty string is truthy in Ruby, a request carrying the string
  ``"false"`` (the common shape for form/query submissions) burned the secret
  anyway, destroying it against the caller's explicit intent. The greenlight
  check now uses the parsed ``continue`` boolean, so only a genuine truthy
  confirmation burns the secret.

- The "Receipt state transition" audit log lines now record the actual secret
  identifier. ``Receipt#revealed!``, ``Receipt#burned!`` and ``Receipt#expired!``
  cleared ``secret_identifier`` to an empty string before building the log
  payload, so every reveal/burn/expire event was logged with ``secret_id: ""``
  — defeating the trail for incident review. The identifier is now captured
  before it is cleared (matching ``orphaned!``), so the log reflects which
  secret the event refers to.

- ``Onetime::Utils.strand`` now draws every character of a generated secret from ``SecureRandom``. The complexity branch (used by default when more than one character set is enabled) previously seeded the guaranteed one-per-set characters with ``Array#sample`` and produced the final ordering with ``Array#shuffle``, both of which fall back to Ruby's non-cryptographic Mersenne Twister PRNG. Generated passwords are now fully CSPRNG-backed; there is no change to length, character sets, or the one-char-per-set guarantee. (#3452)

- MFA OTP setup now fails visibly instead of advancing to a blank QR scan step when a setup response omits ``provisioning_uri``. The 422 (HMAC) path already failed loudly on this; the 200 (non-HMAC) path silently set an undefined ``qr_code``. Both paths now share a ``renderSetupQr`` helper. (#3455)

.. _changelog-v0.25.9:

v0.25.9 — 2026-06-09
====================

Added
-----

- **On-demand heap dumps**: Added opt-in ``SIGUSR2``-triggered heap dumps (via ``HEAP_DUMP_ENABLED``) for diagnosing process memory growth. Includes a ``scripts/analyze-heapdump`` analysis utility. (#3366)

Security
--------

- **Heap dump safety**: Dumps are disabled by default, written owner-only (``0600``) via ``O_EXCL``, and may contain plaintext secrets. Operators should treat dump files as sensitive credentials. (#3366)

AI Assistance
-------------

- Heap dump boot initializer, analysis script, and tests drafted with AI assistance. (#3366)

.. _changelog-v0.25.8:

v0.25.8 — 2026-06-06
====================

Added
-----

- **SSO self-heal**: Legacy users signing in via domain SSO now automatically adopt their domain organization as their default workspace. (#3336)
- **Organization soft-archival**: Added ``Organization#archive!``, ``archived?``, and ``unarchive!`` methods. (#3336)
- **Familia storage migration**: Added migration ``20260606_01_unique_index_json_to_raw`` to rewrite legacy JSON-encoded indexes to the raw format required by Familia 2.10, restoring broken custom-domain SSO lookups. (#3347)
- **Index validation**: Added a boot-time warning if any legacy JSON-encoded indexes remain, including the exact remediation command. (#3347)

Changed
-------

- Upgraded Familia to v2.10.1. Unique index keys are now stored as raw strings rather than JSON-encoded strings. (#3336, #3347)

Fixed
-----

- Tryouts calling writes on unsaved parent objects now save first, satisfying Familia v2.10's strict validation rules. (#3336)

.. _changelog-v0.25.6:

v0.25.6 — 2026-06-01
====================

Changed
-------

- **Config split enforcement**: ``CustomDomain#allow_public_homepage?`` and ``allow_public_api?`` now fail closed (returning ``false``) if their corresponding config records are missing, migrating completely away from the retired ``BrandSettings`` fallbacks. (#3026)
- **Auto-bootstrapping configs**: ``CustomDomain.create!`` now automatically boots default-disabled ``HomepageConfig`` and ``ApiConfig`` records, keeping configuration structures in sync. (#3026)
- **Recipient configuration consolidation**: Removed legacy domain recipient endpoints and the ``IncomingSecretsConfig`` model. Consolidated all recipient storage into the ``CustomDomain::IncomingConfig`` model. (#3095)
- **Structured logger cleanup**: Narrowed ``Billing`` logs to payments, routing subscription entitlements to ``Ents`` logs (filterable via ``DEBUG_ENTS=1``). Unified database logging under the ``DEBUG_DATABASE`` environment variable. (#3257, #3274)

Removed
-------

- **Retired brand configurations**: Fully removed the legacy ``allow_public_homepage`` and ``allow_public_api`` fields from ``BrandSettings``, their API endpoints, frontend schemas, and administrative views. (#3026)

Fixed
-----

- **Recipient management**: Fixed a bug where saving domain recipients would overwrite existing entries by moving to a merged PUT payload model on plaintext recipients. (#3095)

Deployment
----------

- **Action Required**: Operators must run the ``migrate_incoming_secrets_to_config`` housekeeping chore during deployment to migrate legacy recipient records before traffic resumes::

      bin/ots housekeeping run Onetime::CustomDomain migrate_incoming_secrets_to_config

  (#3095)

.. _changelog-v0.25.0:

v0.25.0 — 2026-04-29
====================

Changed
-------

- **Atomic invite acceptance**: Consolidated the invitation login flow to accept invitations atomically during login, eliminating race conditions and reducing API roundtrips. (#2897)
- **Atomic domain configuration**: Added ``find_or_create_for_domain`` to ``HomepageConfig`` and ``ApiConfig`` using Familia's atomic transaction primitives to avoid concurrent write clobbering. (#3023)

Removed
-------

- Removed the unused ``ots:migration_needed:db_0`` Redis write on application boot, saving one round-trip per startup. (#3027)

Fixed
-----

- **Homepage configuration backfill**: Added a migration to preserve public homepage settings for existing custom domains using the new split configuration architecture. (#3023)
- **Cascading domain deletion**: Updated ``CustomDomain#destroy!`` to reliably clean up companion configuration records, preventing orphan Redis keys. (#3023)
- **Organization lookup restoration**: Restored organization email indexes destroyed by automated cleanup logic during membership activation. (#3023)
- **Thread-safe unique index validation**: Refactored domain claiming to run unique-index validations outside of MULTI blocks, resolving intermittent concurrent verification failures. (#3025)

.. _changelog-v0.24.2:

v0.24.2 — 2026-03-14
====================

Added
-----

- ``Middleware::LocaleFallback`` Rack middleware applies the ``fallback_locale``
  config chains after Otto's initial locale detection. When a user's exact
  regional variant is unavailable, the middleware walks the configured chain to
  find the best available match (e.g. ``fr-CA`` falls back to ``fr_FR`` when
  ``fr_CA`` is not available).

- Regression tests: 29 Vitest tests for frontend locale detection, 79 RSpec
  examples for server-side locale mapping and fallback chain resolution.

Changed
-------

- Promoted 10 locales from ``incomplete`` to fully supported: ar, ca_ES, cs,
  he, hu, pt_PT, ru, sl_SI, vi, zh. Added eo (Esperanto). All 30 locales are
  at 92-94% translation coverage. The ``incomplete`` config section has been
  removed.

- Expanded ``fallback_locale`` chains to cover all regional variants (ca, da,
  el, mi, pt-BR, pt-PT, sl, sv) so related locales degrade gracefully.

Fixed
-----

- Browser language detection now works for regional locale variants (e.g.
  ``it-IT``, ``fr-FR``, ``pt-BR``). Previously, 13 of 19 production locales
  failed Accept-Language auto-detection, causing users to see English instead
  of their language. Issue #2668

- Frontend ``navigator.language`` is now read during store initialization, so
  anonymous users on public pages (e.g. secret reveal) get the correct language
  instead of always falling back to English. Issue #2668

AI Assistance
-------------

- Claude assisted with implementing the locale fallback middleware, wiring
  ``navigator.language`` into the frontend store initialization, and writing
  test coverage for both server and frontend locale detection.

.. _changelog-v0.24.1:

v0.24.1 — 2026-03-12
====================

Added
-----

- V1 API validation tooling: ``v1-capture.sh`` records request/response pairs
  from a running instance; ``v1-diff.sh`` compares two captures and flags field,
  type, status code, and header changes. Located in
  ``scripts/api-validation/bin/``. Issue #2615

Changed
-------

- V1 API is now frozen. No new fields or endpoints; new functionality targets
  V2/V3. All V1 responses emit v0.23.x field names and state values for
  backward compatibility with existing integrations. Issue #2615, PR #2626

Fixed
-----

- V1 receipt and secret decryption for Familia v2 compatibility (P0)
- ``NoMethodError`` in ``show_receipt_recent`` — now returns Receipt objects (P0)
- Field name mapping: ``identifier`` -> ``metadata_key``, ``secret_identifier``
  -> ``secret_key``, ``has_passphrase`` -> ``passphrase_required``,
  ``recipients`` -> ``recipient``, ``receipt_ttl`` -> ``metadata_ttl``,
  ``secret_value`` -> ``value``
- State value translation: ``previewed`` -> ``viewed``, ``revealed`` ->
  ``received``, ``shared`` -> ``new``
- ``custid`` emits customer email address (not internal UUID)
- ``share_domain`` returns empty string instead of null
- ``received`` timestamp falls back to ``revealed`` when empty

AI Assistance
-------------

- Claude assisted with debugging V1 compatibility regressions, designing the
  ``receipt_hsh`` field mapping, and writing validation tooling and test
  coverage.

.. _changelog-v0.24.0:

v0.24.0 — 2026-03-05
====================

<!-- SafeDump DSL migration for Familia v2.0.0-pre12 upgrade -->

Added
-----

- UUIDv7 refinements for SecureRandom, String, and Time classes with methods for generating and extracting timestamps from UUIDv7s.

- New unified session architecture using standard Onetime::Session store
- Authentication adapter pattern supporting both Redis-backed auth and future Rodauth integration
- Session helpers extracted to dedicated modules for cleaner controller code
- CSRF protection via shrimp tokens now integrated with Rack sessions

- Database migration 002_add_external_id.rb to support Otto's derived identity integration with unique indexing
- Redis session compatibility methods for validating Otto-linked authentication state

- Identity resolution middleware integrated across all applications (API v1, v2, Web Core)
- Dual authentication mode support (basic Redis vs Rodauth) with automatic detection
- External ID lookup functionality in Onetime::Customer for Otto-Rodauth identity bridging
- RodauthUser class for unified user representation with full feature access

- Account closure with automatic Otto customer cleanup in Rodauth after_close_account hook
- Enhanced V2 authentication strategies to use identity resolution middleware across all strategy types

- Comprehensive authentication configuration system with YAML-based mode control
- Authentication migration guide with step-by-step procedures and troubleshooting
- Database migration tools for customer linking and session preservation during auth mode switches
- Configuration-based authentication mode detection with environment variable fallbacks
- Rollback migration tools for safe auth mode reversal

- Git JSON merge driver for automated locale file conflict resolution. Semantic 3-way merging automatically resolves non-conflicting changes in ``src/locales/**/*.json`` files, preserving keys added on different branches without manual conflict resolution.
- ``.gitattributes`` configuration for locale JSON files to enable the custom merge driver.

- Secret reveal notifications: Users can now opt-in to receive email notifications when their secrets are viewed. Enable this feature in Account Settings > Notifications.
- New notification settings page at ``/account/settings/profile/notifications`` for managing email notification preferences.
- ``notify_on_reveal`` field on Customer model to store user notification preference.

- Dashboard experience variants: The dashboard now adapts based on user capabilities and team count, showing appropriate views for free users, single-team users, and multi-team users.
- Self-hosted feature parity: Full capabilities granted when billing is disabled for opensource/self-hosted installations.
- Team-count driven UX with onboarding flow for users with no teams.

- Development process manager (``bin/dev``) for single-command startup of backend, frontend, and worker processes using Overmind.
- Setup script (``install-dev.sh``) to symlink shared dev resources from ``~/.config/onetimesecret-dev``, run ``bundle install``, and run ``pnpm install``, enabling consistent multi-worktree development.
- New ``Procfile.dev`` defining development services: Puma backend (port 7143), Vite frontend, and background worker.

- New ``DlqEmailConsumerJob`` scheduled job replays auth-critical emails from
  the dead-letter queue (``dlq.email.message``) on a 5-minute cycle. Raw
  Rodauth emails (password reset, verify account, email change) are always
  replayed; templated auth emails are replayed only if the underlying Rodauth
  key is still valid; non-auth emails (secret links, expiration warnings) are
  discarded as stale. Enabled by default; set
  ``JOBS_DLQ_CONSUMER_ENABLED=false`` to disable. PR #2530

Changed
-------

- Updated all models to use the new SafeDump DSL, replacing the brittle ``@safe_dump_fields`` class instance variable pattern with clean, explicit ``safe_dump_field`` method calls. This improves code maintainability and follows the modern Familia v2.0 patterns.

- Customer migration now uses deterministic external ID generation based on UUID hash instead of random values.
- Session cleanup migration updated to use Familia::Refinements::TimeLiterals instead of custom time extensions.

- Controllers now use env['onetime.session'] instead of custom Onetime::Session model
- Identity resolution middleware updated to read from standard Rack sessions
- Session persistence moved from custom Familia model to Rack::Session standard
- Colonel stats tracking simplified with session counting removed (handled by middleware)

- Refactored API v2 authentication strategies to use Otto 1.5+ class-based architecture instead of lambda functions. This improves maintainability, error handling, and type safety while providing better structured authentication results. Issue #1619

- Updated API v2 logic layer to use Otto RequestContext for consistent request state management across the application. This provides better encapsulation of session, user, auth method, and request metadata. Issue #1619

- Integrated Otto customer creation with Rodauth account registration, automatically linking new accounts with derived Otto external IDs
- Unified session management by replacing Roda sessions with Redis-backed Onetime::Session for consistency across applications
- Enhanced session validation with Otto integration checks and configurable session expiration
- Updated session cookie configuration for unified naming convention (onetime.session, onetime.remembers)

- Identity resolution middleware now supports both Redis-only and Rodauth authentication modes
- All application middleware stacks updated to include centralized identity resolution
- Customer lookup enhanced with find_by_extid method for external identity resolution
- Authentication flow unified across applications with consistent user object interfaces

- V2SessionStrategy updated to leverage pre-resolved identity from IdentityResolution middleware
- V2CombinedStrategy refactored to prioritize identity resolution over basic auth with intelligent fallback
- V2OptionalStrategy enhanced with identity-aware anonymous access and improved authentication flow
- All authentication strategies now support both Rodauth and Redis session sources with unified metadata

- Updated authentication configuration structure with unified session settings and mode-specific configurations for basic and advanced auth modes.
- Enhanced AuthConfig class to support environment variable overrides and improved error handling with detailed configuration guidance.

- Publisher now supports configurable fallback strategies when RabbitMQ is
  unavailable: ``:async_thread`` (default, non-blocking), ``:sync`` (blocking),
  ``:raise`` (error), or ``:none`` (silent fail). This replaces the previous
  3-second retry delay that could block Puma threads during outages. PR #2064

- Critical auth flows (password reset, Rodauth emails) use ``:sync`` fallback
  to ensure delivery; non-critical paths (feedback) use ``:none`` to avoid
  thread proliferation.

- Renamed TeamDashboard component to TeamView for naming consistency.
- API parameter access standardized from symbol keys to string keys across account, teams, and secrets APIs.
- Team updates now use PUT instead of PATCH for full resource replacement semantics.

- **Frontend Architecture**: Restructured Vue application from flat `views/` and `components/` directories to domain-driven `apps/` structure with five interaction modes: Secret (transactional flows), Workspace (management), Session (authentication), Kernel (admin), and Billing (commerce). This migration moves ~116 files, creates 15 new files, and removes 18 redundant files. PR #2114

- Simplified ``.env.example`` by removing shell export directives and adding explicit ``NODE_ENV=production``.
- Added ``.env.sh`` symlink convention for environment sourcing.

- Replace WindowService with Pinia-based bootstrapStore as single source of truth for server-injected state
- Rename window variable from ``__ONETIME_STATE__`` to ``__BOOTSTRAP_ME__`` and delete it immediately after consumption

- DLQ message TTL is now managed via a RabbitMQ policy (``dlq-ttl``) rather
  than queue arguments. Policies are mutable at runtime; queue arguments are
  not, and caused ``PRECONDITION_FAILED`` errors on worker startup when TTL
  config changed. PR #2529

- ``bin/ots queue init`` now applies the ``dlq-ttl`` policy as step 4 via the
  Management API. ``bin/ots queue status`` reports active DLQ policies.

**Upgrading existing installs** (environments with DLQ queues declared before
this release):

.. code-block:: bash

   # Check DLQ message counts — any messages are failed jobs already dead-lettered
   bin/ots queue status

   # Stop workers, then delete and recreate all queues (destroys DLQ messages)
   bin/ots queue reset --force

   # Recreate infrastructure and apply the dlq-ttl policy
   bin/ots queue init

   # Restart workers and verify
   bin/ots queue status

If DLQ messages must be preserved, drain them before resetting (requeue or
archive via the Management UI), then proceed with the reset.

Removed
-------

- V2::Session model and all associated custom session management code
- SessionMessages mixin (functionality moved to standard session handling)
- ClearSessionMessages middleware (no longer needed with Rack::Session)
- Custom session-based tryout tests replaced with Rack::Session approach
- Deprecated customer session management methods

- NewRelic monitoring dependency from auth service production Gemfile (moved to application-level configuration)

Fixed
-----


- Fixed NameError in ShowSecretStatus API logic where `@realttl` instance variable was referenced as undefined `current_expiration` method
- Fixed syntax errors in Team and Organization models where double dots (`team..to_s`, `org..to_s`) caused parsing failures

- Auth service now properly loads Vite assets in both development and production modes, eliminating style flash and Vue app initialization errors
- Development mode loads scripts from Vite dev server with proper URL configuration for hot module replacement
- Production mode uses compiled manifest with optimized asset loading and font preloading
- Removed duplicate window.__ONETIME_STATE__ initialization that was causing conflicts
- Fixed hardcoded frontend_development flag to use dynamic configuration
- Improved script placement consistency with core app (all assets loaded in head section)
- Added critical CSS to prevent flash of unstyled content during asset loading
- Enhanced ViteAssets helper with proper dev server URL support and configuration awareness

- Fixed Redis session key reference in identity resolution middleware. Issue #1679
- Fixed missing Singleton require in auth configuration module.
- Fixed relative path in customer migration script for proper module loading.

- Fixed undefined variable `expire_after` in Rodauth session validation by using configured expiry values
- Fixed customer creation to pass email string directly instead of hash parameter
- Fixed malformed newline string literals in error backtrace output
- Fixed auth mode detection logic to properly load and use centralized configuration system
- Fixed hardcoded session expiry values to use configurable timeout settings

Documentation
-------------

- AUTHENTICATION_MIGRATION.md with complete migration procedures and rollback instructions
- Authentication configuration reference with environment-specific overrides
- Migration tool documentation with dry-run and live execution modes
- Troubleshooting guide for common migration scenarios and recovery procedures

- Added Git JSON merge driver setup instructions to README.md Development section.

AI Assistance
-------------

- Systematic migration of 10 model files (both V1 and V2 APIs) from legacy ``@safe_dump_fields`` array syntax to the new DSL. AI assistance included code analysis, pattern identification, and bulk refactoring while preserving all existing functionality and field definitions.

- Automated PR review feedback analysis identified critical runtime errors that were systematically fixed

- Session architecture implementation guided by Claude Code per issue #1673

- Significant assistance with refactoring authentication strategy architecture from lambda-based to class-based implementations, ensuring proper inheritance from Otto::Security::AuthStrategy and consistent error handling patterns.

- Used Claude Code to identify and fix session key inconsistencies and module dependencies in Phase 5 of Otto authentication integration.

- Used Claude Code to analyze PR review feedback from multiple automated tools and implement critical runtime fixes based on systematic analysis of identified issues

- RabbitMQ architecture review identified sync fallback as blocking issue.
  Claude assisted with designing the opt-in fallback parameter API and
  Thread.new implementation for Puma compatibility.

- Claude assisted with full-stack implementation including backend (Ruby email templates, API endpoint, reveal flow integration) and frontend (Vue component, Pinia store, TypeScript schema, i18n strings).

- Claude assisted with dashboard variant architecture, capability-based routing, and component refactoring.

- Claude Code assisted with planning the migration strategy, generating the migration manifest, and updating import paths across the codebase.

- Claude Code assisted with PR feedback implementation: security improvements (removing auto-install behavior), path traversal validation, and shell script best practices.

- Claude assisted with implementation of ``DlqEmailConsumerJob``, including
  idempotency design, token expiry validation, channel management, and
  tryout test coverage.

- Claude assisted with debugging CI test failures in the DLQ policy filter
  and nil/empty-array return value semantics for the Management API client.
