CHANGELOG
=========

All notable changes to Onetime Secret are documented here.

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__, and
this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

.. _changelog-0.26.19:

0.26.19 — 2026-10-24
====================

Added
-----

- Custom domain homepages support IPv4/IPv6 allow and deny lists for
  anonymous secret creation. Denied visitors see the private landing page.
  These rules do not restrict secret links, member access, management
  pages, ``/incoming`` or the incoming API; they also control whether the
  incoming form appears at the homepage. Both lists are empty by default.

  Workspace and API editing requires the ``homepage_network_rules``
  entitlement and ``ORGS_HOMEPAGE_NETWORK_RULES_UI_ENABLED=true`` (default
  off); the Colonel editor is not gated by the flag. With billing enabled,
  add the entitlement to the intended plans in the installation's
  ``etc/billing.yaml`` and push the catalog; see
  ``etc/examples/billing.example.yaml``. Stored rules remain enforced after
  a downgrade or with the flag off; the API then refuses list changes and
  deletion of a config with rules. Check ``site.network.trusted_proxy``
  before configuring rules behind a proxy. See ``etc/config.yaml``.
  (#4757, #4834)

- Custom domain signup allowlists can include the domain's own base domain
  without listing it explicitly: ``secrets.acme.com`` can admit
  ``@acme.com``. Use ``allow_base_domain`` with the ``domain_allowlist``
  validation strategy on the workspace Signup Validation page.

  Enable ``ORGS_BASE_DOMAIN_SIGNUP_ENABLED=true`` and grant the
  ``base_domain_signup`` entitlement; both are checked at signup. No billing
  plan grants the entitlement by default; standalone installs grant every
  entitlement. If the datastore or plan catalog cannot be read, signups
  needing the base-domain check return 503. See ``etc/config.yaml`` and
  ``apps/web/billing/docs/plan-definitions.md``. (#4756)

- Custom domain SAML settings can import the IdP SSO URL, EntityID and a
  selected signing certificate from a metadata URL. For Entra, use the App
  Federation Metadata Url. Review the preview, apply it and save the form;
  fetching alone changes nothing. This does not enable automatic metadata
  or certificate refresh. ``POST /api/domains/:extid/sso/metadata`` allows
  30 requests per customer per hour by default
  (``SSO_METADATA_FETCH_RATE_LIMIT_*``). (#4850)

- Added commands to remove closed authentication accounts and their audit
  logs, and finish interrupted customer closures. After upgrading, preview
  and then confirm ``bin/ots customers prune-closed-accounts``, followed by
  ``bin/ots customers finish-closures``. Both preview by default; use
  ``--confirm`` to delete.

  Export audit records first if retention requirements need them. Outside
  the shipped containers, export ``AUTHENTICATION_MODE`` as ``full`` or
  ``simple`` to match the installation before confirming
  ``finish-closures``. See ``docs/development/data-migrations.md`` for
  selection, repair and cleanup guidance. (#4819, #4830)

- Administrators can set a member's default organization with
  ``bin/ots customers set-default-org CUSTOMER ORG --apply`` or
  ``bin/ots memberships add ORG CUSTOMER --default --apply``. (#4858)

Changed
-------

- Account closure in full authentication mode deletes the authentication
  account and its authentication audit history on PostgreSQL and SQLite.
  Administrative purges and the simple-mode delete endpoint remove the
  same data. Signing up again with the address creates a new account. For
  existing closed accounts, follow the cleanup procedure in
  ``docs/development/data-migrations.md``. (#4819)

- Customer diagnostics report interrupted account closures, and
  ``customers sync-auth-accounts`` skips them. A subsequent signup finishes
  the old closure before creating a new customer record.
  ``customers doctor --repair`` clears markers for closures that rolled
  back. See ``docs/development/data-migrations.md``. (#4830)

- Organization administration uses ``bin/ots organizations``;
  ``organization`` and ``org`` remain aliases. Replace ``--list``,
  ``--show`` and ``--check`` with ``list``, ``show ORG`` and
  ``doctor --all``. Replace ``add-member`` with
  ``bin/ots memberships add ORG CUSTOMER [--role R] [--default] --apply``.
  ORG accepts public or internal organization IDs, Stripe customer or
  subscription IDs, and custom domain hostnames; customer arguments also
  accept internal IDs. See command help for options and integrity checks.
  (#4858)

- **Scripts that write through bin/ots may need --apply.** These verbs
  are now dry runs unless given ``--apply`` and no longer prompt:
  ``organizations create``, ``delete``, ``transfer-ownership``,
  ``reconcile``, ``unarchive`` and ``entitlement grant|revoke|clear``;
  ``memberships add``, ``remove``, ``set-role`` and ``entitlement
  grant|revoke|clear``; ``customers set-default-org``, ``change-email`` and
  ``role reconcile``; ``domains remove``, ``repair`` and ``transfer``;
  ``banner set`` and ``banner clear``. ``--yes`` and ``-y`` remain aliases
  for ``--apply``, except on ``change-email``, which ignores them. A piped
  confirmation (``echo y | bin/ots organizations delete ORG``) now previews
  and exits 0. ``organizations list --owner`` or ``--plan`` reports the
  size of its walk unless given ``--run``. ``customers role reconcile`` is
  its own subcommand, so ``role promote`` and ``demote`` reject ``--apply``
  and ``--json``. (#4858, #4861)

- The Colonel console supports password elevation before protected
  actions, advance elevation with a countdown, and password renewal of an
  expired admin session. Administrators can change or remove organization
  memberships and set a customer's default organization. The user-menu
  Admin link opens in the same window. See
  ``docs/operations/colonel-admin-guide.md``. (#4858)

- Authentication uses Rodauth 2.48 from the onetimesecret fork, updated
  from 2.45. Signed-in users receive 403
  ``{"error":"Already logged in"}`` on login, signup, account verification,
  magic-link login, passkey login and account-unlock routes, rather than
  switching accounts through a verification or magic link. Sign out before
  following a link for another account. Password reset and sessions not
  yet marked authenticated are exempt. (#4822, #4840)

- The frontend loads route code on demand. Failed route loads offer a
  reload notice, with automatic reload attempts limited to once per tab
  per minute and suppressed while one-time values are displayed. See
  ``docs/adr/adr-046-bootstrap-state-ordering-contract.md``. Custom asset
  integrations must use ``.vite/manifest.json`` instead of the removed
  ``.vite/manifest-admin.json``. Production ``script-src`` remains
  nonce-only. (#4846)

- Non-English translations load on demand. ``?locale=`` also applies to
  signed-in pages for the browser session without changing the account
  preference. Page titles and the HTML language tag follow language
  switches, using BCP 47 tags such as ``pt-BR``. Languages absent from the
  build are not offered; an initial language load failure falls back to
  the default language or English with a notice. (#4846)

- Receipt and burn responses no longer provide share links for revealed,
  burned, expired or orphaned secrets. API clients must handle unavailable
  links: ``share_path`` and ``share_url`` can be ``null``, v2/v3
  ``secret_identifier`` can be absent, and v1 ``secret_key`` can be empty
  or absent. A burn can return 404 if its receipt disappears during the
  request even though the secret was destroyed. (#4835)

- SAML configuration rejects EntityIDs containing unresolved brace
  placeholders such as ``{tenantid}``. Replace them with the tenant's
  actual EntityID before saving, testing or re-enabling domain SSO;
  existing configurations can still be disabled. A placeholder in
  ``SAML_IDP_ENTITY_ID`` prevents platform SAML from being enabled. See
  ``docs/authentication/per-domain-sso.md`` and
  ``docs/authentication/per-install-sso.md``. (#4850)

- The domain signup-config API reports ``uses_allowlist``;
  ``requires_allowlist`` remains as a deprecated alias. PATCH updates that
  omit all allowlist inputs are no longer rejected because of the stored
  list. The Colonel editor refuses invalid configuration changes but still
  permits disabling or repairing an invalid config. (#4756)

Removed
-------

- Removed the deprecated model-level ``secret_key`` field from receipts
  and secrets. No data migration is required. The v1 API continues to use
  ``secret_key`` as its response field name, subject to receipt visibility
  rules. (#4835)

- Removed ``Onetime::Jobs::Publisher.schedule_email`` and the
  ``email.message.schedule`` queue. Once no running process uses the old
  publisher, delete the retired durable queue with
  ``rabbitmqctl delete_queue email.message.schedule``. See
  ``lib/onetime/jobs/queues/maintenance.md``. (#4844)

Fixed
-----

- Fixed expiration warnings being discarded without delivery when the job
  system is enabled. Warnings are dispatched when a scan processes the
  secret within the warning window and link to the owner's recent secrets
  page instead of a broken secret link, without including receipt or
  secret identifiers. Previously queued warning payloads are rejected as
  invalid. (#4844)

- Signed-out visitors return to the requested page after signing in.
  Return destinations must be internal paths; POST requests are not used
  as return destinations. (#4844)

- In simple authentication mode, emailed verification links work without
  an existing session. Verification through the v1 API no longer produces
  a server error after verifying the account. Secret confirmation forms
  display errors without requiring a passphrase and remain in the
  submitting state during the request. (#4831, #4832, #4842)

- Passkey signup with ``AUTH_WEBAUTHN_VERIFY_ACCOUNT=true`` completes
  customer verification, pending federated subscription activation,
  branded verification email and resend handling even when
  ``AUTH_VERIFY_ACCOUNT_ENABLED=false``. Verification also works with
  ``AUTH_MFA_ENABLED=true``, including recovery-code creation and
  verification-key cleanup (onetimesecret/rodauth#3). (#4829, #4837, #4840)

- Successful ``POST /receipt/{id}/burn`` requests return the updated
  receipt state across v1, v2 and v3, including the ``/private`` and
  ``/metadata`` aliases. Burn previews with ``continue=false`` follow the
  same secret-identifier visibility rules as receipt reads. v1
  ``GET /receipt/{id}`` returns complete ``metadata_url`` and
  ``receipt_url`` values and does not expose secret keys for consumed or
  missing secrets. (#4835)

- Regional language fallbacks, including ``de-AT``, ``fr-CA`` and
  ``pt-BR``, work in the browser. (#4846)

- Server-rendered pages preload fewer fonts. Canonical and social URLs
  use the served host and public port without query strings, so custom
  domain pages no longer advertise the installation's canonical host.
  (#4859)

- Secret and receipt pages (``/secret/*``, ``/receipt/*`` and
  ``/incoming/:receiptKey``) emit ``noindex, nofollow`` and neutral social
  preview text that does not name the page. (#4859)

Security
--------

- The v1 receipt API, including its ``/private`` and ``/metadata`` aliases,
  no longer exposes an incoming secret's key to someone with its receipt
  identifier, including the guest who submitted it. Burn previews with
  ``continue=false`` also omit the incoming secret's share link. (#4835)

.. _changelog-0.26.18:

0.26.18 — 2026-10-17
====================

Added
-----

- ``bin/ots domains resolve-collisions`` writes a reviewable plan for
  duplicate custom domain records that share one name. Applying a plan
  deletes the duplicates' settings and branding without merging them into
  the kept record. Stop all custom domain writers and snapshot the
  datastore before applying; follow
  ``docs/runbooks/custom-domain-ascii-index-backfill.md`` for plan review,
  required approvals and application. (#4807)

- Production builds print a self-XSS warning in the browser console.
  (#4804)

Changed
-------

- The custom domain name index is renamed to the ASCII index. The key
  ``custom_domain:canonical_display_domain_index`` becomes
  ``custom_domain:ascii_display_domain_index``, and ``bin/ots domains
  backfill-canonical-index`` becomes ``bin/ots domains backfill-ascii-index``.
  Update scripts and regenerate collision plans from older rule versions.
  (#4807)

  **Before starting the new release**, deployments with the former index
  key must migrate it. With web, worker and scheduler stopped, preview
  ``bin/ots migrate migrations/2026-10-15/20261015_01_rename_ascii_display_domain_index.rb``,
  then repeat with ``--run``. Without the rename, the application sees an
  empty ASCII index. Follow
  ``docs/runbooks/custom-domain-ascii-index-backfill.md`` for preparation
  and validation.

- Customer purge commands are renamed; update scripts that call them.
  ``bin/ots customers purge IDENTIFIER`` deletes one account (was
  ``purge-one``, which is gone). ``bin/ots customers purge-inactive
  --older-than DURATION`` is the bulk sweep (was ``purge``); it previews
  unless given ``--purge``, and ``purge --older-than`` is rejected. (#4806)

- Domain removal responses from the CLI (JSON) and the Colonel API drop
  ``reasserts_survivor`` and add ``sender_cleanup``: ``deleted``,
  ``absent``, ``skipped`` or ``failed`` after removal, and ``null`` during
  previews. Update response consumers. Failed sender cleanup does not undo
  local domain deletion; ``bin/ots domains remove`` then exits 1. Inspect
  the failure log and remove the remaining sender identity at the provider:
  rerunning removal cannot retry cleanup. See
  ``docs/development/domain-sender-lifecycle.md``. (#4798, #4814)

- Lettermint sender domain removal uses ``lettermint`` 0.2.1. A 404 with
  ``RESOURCE_NOT_FOUND`` counts as already absent; any other 404 is a
  failed cleanup. Logged Lettermint errors include the API error code.
  (#4814)

Fixed
-----

- Custom domain lookups refuse and log an index entry that points to a
  record stored under a different name, instead of serving that record.
  Existing drift still needs repair; run ``bin/ots domains doctor --all``.
  (#4798)

- Deleting a custom domain releases its name-index entries by the stored
  name, without removing entries owned by another record that shares the
  hostname. Fixed a save-versus-deletion race that could recreate a deleted
  domain.
  (#4798)

- Reduced datastore work during preflight for single-account customer
  purges. (#4806)

- SendGrid domain listings are read to the last page, and sender domains
  match case-insensitively. (#4814)

- Cancelling an organization switch at the unsaved-changes prompt keeps the
  current organization, edits and domain list. (#4802, #4809)

.. _changelog-0.26.17:

0.26.17 — 2026-10-15
====================

Added
-----

- Opt-in Markdown secrets with live preview, syntax highlighting and a raw
  source view. Enable ``MARKDOWN_ENABLED=true``; the API accepts
  ``display_type: markdown``. Rendering strips remote-loading content and
  shows links as non-clickable text. With Markdown disabled, new Markdown
  secrets are rejected with 422 and existing ones display as plain text;
  re-enabling restores their rendered view. Generated passwords stay plain
  text.

- Generic OIDC supports ``client_secret_basic`` (default) and
  ``client_secret_post`` through the domain SSO form or platform
  ``OIDC_CLIENT_AUTH_METHOD``. Test Connection warns about methods the IdP
  does not advertise. Existing configurations are unchanged; see
  ``docs/authentication/per-domain-sso.md``. (#4764)

- "Check saved configuration" diagnoses domain SSO settings, provider
  discovery, SAML certificates and Entra client secrets. Entra credential-probe
  results omit secrets, tokens and Microsoft error text; audit records omit
  provider messages. Checks default to 10 per customer per hour
  (``SSO_DIAGNOSTICS_RATE_LIMIT_*``). The Entra secret field also warns about
  entering a Secret ID instead of its Value. A passing check does not confirm
  sign-in works; complete a real sign-in after setup or credential rotation.
  See ``docs/runbooks/sso-credential-health.md``.

- Domain SSO settings show the latest sign-in outcome and failure step,
  retaining the last success alongside later failures. Records expire after
  90 days without a sign-in. Diagnostics and outcomes support all 29 locales.

- ``bin/ots domains backfill-canonical-index`` repairs missing domain-name
  index entries; ``bin/ots domains doctor --all`` reports missing entries
  and duplicate names. For pre-v0.26.14 domains, preview the backfill, then
  stop all domain-writing application processes and snapshot the datastore
  before applying it. Follow the
  `v0.26.17 backfill runbook <https://github.com/onetimesecret/onetimesecret/blob/v0.26.17/docs/runbooks/custom-domain-canonical-index-backfill.md>`__.
  (#4780)

Changed
-------

- Tenant SSO failure logs include the domain id for troubleshooting.

- Orphaned domain records require explicit operator adoption through
  ``bin/ots domains create``, ``repair --org-id``, ``transfer`` or the
  Colonel API. Adoption preserves settings, branding and receipts but
  resets ownership verification and issues a new TXT challenge.

- Under ``approximated`` and ``caddy_on_demand``, unverified custom domains
  now return 404 and cannot be used for new links. Keep TXT verification
  records published; losing verification also stops serving unless a
  Colonel override keeps it verified. ``passthrough`` still requires only
  registration to an organization; orphaned records are never served.

  **Before upgrading**, run ``bin/ots domains verify --all`` and
  ``bin/ots domains orphaned``; resolve unverified or orphaned domains still
  in use. After changing ``validation_strategy``, re-run verification before
  accepting traffic. ``DOMAINS_SERVE_UNVERIFIED=true`` temporarily restores
  prior serving behavior for organization-owned domains and warns at boot.
  See ``features.domains`` in ``etc/defaults/config.defaults.yaml``.

- Domain SSO configuration moves from a dialog to a dedicated settings page.
  Existing ``?modal=sso`` links redirect there, and navigation warns before
  discarding unsaved changes.

Fixed
-----

- Leaving domain DNS setup stops widget background activity and ignores
  late responses instead of raising errors.

- Platform and custom-domain Entra sign-in no longer corrupt client secrets
  containing ``+`` or ``%`` during token exchange. No configuration change
  is needed; generic OIDC and SAML are unchanged. (#4764)

- Unicode subdomains can be registered and verified using A-label TXT
  records. Excessively deep names or oversized TXT record names return a
  validation error instead of a server error. (#4780)

- Concurrent domain-configuration edits preserve unrelated changes,
  validate against current settings and produce accurate audit records.
  Conflicting updates return ``conflict`` rather than overwriting newer
  settings. (#4764)

- Email sender checks no longer apply stale results after an address change
  or recreate deleted settings. Provisioning and deletion are coordinated
  to avoid orphaned sender domains at the mail provider; overlapping
  removals return ``conflict``. (#4764)

- The optional ``jobs.maintenance.index_rebuild`` job no longer reports
  false mismatches or damages indexes when ``auto_repair`` is enabled. If
  earlier repair runs affected indexes, run the corrected repair and review
  its report; conflicting entries require manual resolution. The job remains
  off by default. See ``jobs.maintenance.index_rebuild`` in
  ``etc/defaults/config.defaults.yaml``.

- Domain and membership doctor commands correctly detect and remove stale
  collection entries; ``--repair`` reports actual removals. Customer purge
  reports recognize Stripe billing through organization membership.

- Switching domains warns before discarding unsaved settings. Domain-page
  headers fit their content and mobile screens, and localized SSO dates no
  longer produce doubled punctuation.

- Customer purges resume after organization deletion left legacy membership
  references, without a separate doctor repair. Organization deletion also
  cleans up those references; remaining dependent data still blocks purging.

Security
--------

- Removed CSP nonces from bootstrap payloads to reduce exposure through
  HTML injection. (RISK-2026-08-14-M08)

- Container builds pin ``yq`` to v4.52.4 and verify architecture-specific
  SHA-256 digests before installation. (RISK-2026-08-14-M12)

- DNS setup sanitizes remote provider instructions, removing executable
  markup and automatic remote loads. If sanitization is unavailable,
  instructions display as plain text. (RISK-2026-08-14-M09)

- Guest recent-secret lists no longer persist direct secret-link identifiers
  in browser tab storage; older cached identifiers are removed on load. After
  reloading, guests copy links from the receipt page instead. Receipt links
  remain stored and can still retrieve share links. (RISK-2026-08-14-M10)

- Magic-link and verification-resend requests no longer reveal missing,
  ineligible or recently mailed accounts through distinct response errors.
  **API clients:** ``POST /auth/email-login-request`` and
  ``POST /auth/verify-account-resend`` no longer return ``no_matching_login``
  or "recently sent" errors; success does not confirm delivery. Eligibility
  and resend windows still apply, and invalid or throttled requests can
  still fail. Unsupported email locales fall back, and invalidly encoded
  parameters on available Rodauth routes return 400 before account lookup.
  (RISK-2026-08-14-M03)

- Magic-link requests are rate limited by default: 30 per masked client-IP
  bucket and 90 per submitted address per hour, with a one-hour lockout.
  Passwordless ``POST /auth/login`` shares these limits; verification resend
  still has no per-source limit. Configure
  ``site.authentication.email_login_request_rate_limit`` using
  ``EMAIL_LOGIN_REQUEST_RATE_LIMIT_*``; follow the limit constraints in
  ``etc/defaults/config.defaults.yaml``.
  (RISK-2026-08-14-M04)

  **Before upgrading behind a reverse proxy**, configure trusted client-IP
  resolution or visitors share the proxy's rate-limit bucket. Enabling
  ``TRUSTED_PROXY_ENABLED=true`` also requires safe forwarding-header
  handling: default filter mode requires the edge to overwrite
  ``X-Forwarded-For``. See ``site.network.trusted_proxy`` in
  ``etc/defaults/config.defaults.yaml`` and ``etc/examples/Caddyfile-example``.
  Opt out with ``EMAIL_LOGIN_REQUEST_RATE_LIMIT_ENABLED=false``.

- Opt-in datastore TLS enforcement with ``VALKEY_REQUIRE_TLS=true`` or
  ``REDIS_REQUIRE_TLS=true``. Boot then requires ``rediss://`` or
  ``valkeys://`` with no ``ssl`` query parameter. Plaintext remains allowed
  by default, with boot notices graded by host. See ``redis.require_tls``
  in ``etc/defaults/config.defaults.yaml``. (RISK-2026-08-14-L07)

- Customer self-service email-change confirmations, workspace deletions and
  domain test emails use the Colonel security audit sub-trail (newest 1,000,
  seven days) rather than crowding out operator entries. Colonel-initiated
  workspace deletions and test emails remain in the operator trail. Events
  are also emitted to the ``ColonelAudit`` log stream; longer retention
  requires external collection. Test recipients are obscured. See
  ``docs/architecture/audit-logging.md``.

- Domain sender test emails default to 10 per customer per hour across all
  their domains, including colonels, followed by a one-hour lockout. The form
  reports the wait after a 429. Configure ``SENDER_TEST_EMAIL_RATE_LIMIT_*``
  in ``etc/defaults/config.defaults.yaml``.

.. _changelog-0.26.16:

0.26.16 — 2026-10-11
====================

Added
-----

- GitLab (gitlab.com) as a platform SSO provider. Configure
  ``GITLAB_CLIENT_ID`` and ``GITLAB_CLIENT_SECRET``; custom-domain SSO does
  not support this provider. Use generic OIDC for self-managed GitLab.
  (#4727, #4733)

- Default-workspace selection on the Organizations page and in account
  preferences. Members of multiple organizations can choose where a new
  session starts, including members who own no organization. Saving also
  switches the current workspace. The account-preferences setting is hidden
  on custom domains. (#4701, #4709)

- ``bin/ots org unarchive ORG [--run]`` previews or restores an archived
  organization and records the applied change in the audit log. Previously
  archived organizations are not restored automatically. For tenant
  organizations that archived themselves, deploy this release before following
  the `0.26.16 repair procedure <https://github.com/onetimesecret/onetimesecret/blob/v0.26.16/docs/runbooks/sso-self-archived-organization.md>`__;
  it excludes personal workspaces archived in favor of another organization.
  (#4717, #4723)

- Scheduler liveness, next-run times and latest job results on the Colonel
  Jobs page and through ``bin/ots scheduler status``. (#4729)

- Individual dead-letter message inspection, replay and discard in the
  Colonel Jobs page and CLI. CLI replay and discard accept ``--id``;
  ``--max-scan`` searches beyond the default 500-message bound. (#4729)

- Selected housekeeping chores and billing entitlement materialization can
  run from the Colonel Jobs page, with record limits, confirmation and audit
  records. Entitlement materialization also supports preview. (#4729)

- A Colonel Schemas page for checking JSON payloads against the
  application's API schemas. (#4700)

Changed
-------

- Tenant SSO no longer archives a customer's previous personal workspace
  when making the domain's organization their default. The previous
  workspace remains available; an explicit default pointing to another
  joined organization or an owned non-default workspace is preserved.
  (#4717, #4724)

- Simple-mode password sign-in, Colonel step-up, re-authentication and first
  second-factor setup now renew the session id before granting access. If
  the old session cannot be ended, the operation does not complete. Simple
  sign-in starts a fresh session and returns a new CSRF token; the web app
  adopts renewed sessions without a page reload. (#4466, #4708)

- Homepage ``matching_cidrs`` now supports full IPv4 and IPv6 precision,
  including /32 and /128. Review configured ranges narrower than /24 or /48
  before upgrading: previously ignored entries now take effect.
  ``mode: external`` hides the homepage secret-creation form for matching
  visitors; it does not restrict API access. IP privacy still masks the
  client address seen by the application. See
  ``etc/defaults/config.defaults.yaml``. (#4056, #4704)

- Authenticated requests share one read of organization memberships,
  reducing datastore calls without caching memberships between requests.
  (#4711)

- Email-delivery test messages now explain their purpose to the recipient
  without exposing the provider or sending machine's name. Feedback emails
  link to the user's organizations, and Colonel customer, organization and
  domain links consistently use public ids. (#4700)

Removed
-------

- ``bin/ots domains migrate-sso`` and its bulk SSO migration operation.
  Customers still join a domain's organization through tenant SSO sign-in;
  the default-workspace behavior is described above. (#4717, #4725)

Fixed
-----

- Members of multiple organizations now get the workspace switcher.
  Accepting an invitation switches to the joined organization, and the
  default label and sign-in fallback no longer mistake another owner's
  default workspace for the customer's own. (#4701)

- Billing, entitlement grants, organization-creation quotas and Colonel
  plan displays now resolve the workspace the customer owns, rather than
  another owner's default workspace they joined. The quota counts owned
  organizations, not every membership. Explicit checkout or portal requests
  for an organization the caller does not own remain refused. (#4710)

- Tenant SSO sign-in no longer archives the organization being joined when
  its owner also uses it as their default workspace. (#4717, #4723)

- First SSO sign-in now succeeds when the provider sends a mixed-case email
  address, including Entra guest addresses containing ``#EXT#``. New SSO
  accounts store lowercase addresses, and sign-in uses the account's stored
  customer link before falling back to email lookup. First-time provisioning
  rejects addresses whose canonical lowercase form would be changed by
  Unicode case folding. (#4726, #4730)

- Existing mixed-case SSO account emails can be repaired with
  ``bin/ots customers normalize-emails``. Review the preview before applying
  with ``--confirm``; skipped and errored rows require review. For a
  ``:partial`` result, run ``bin/ots customers doctor <extid>`` before
  retrying. See ``docs/development/data-migrations.md`` for batching and
  unresolved repairs. (#4726, #4731)

- Tenant SSO email-domain allowlists now match Unicode and A-label forms
  of internationalized domains interchangeably. Entries without an exact
  A-label form are rejected when saving the configuration. (#4736, #4751)

- SSO errors now distinguish a missing email claim (``missing_email``) from
  a malformed address (``invalid_email``). First-time provisioning requires
  a usable email; an already-linked platform identity can still sign in
  without a callback email. (#4728, #4738)

- Newly issued magic sign-in links on PostgreSQL and SQLite expire after
  15 minutes instead of the database's 24-hour default. Resending within
  that window does not extend the original deadline; existing key rows are
  not rewritten. (#4703)

- Re-authentication that cannot save its proof after renewing the session
  returns ``503 reauth_not_recorded`` with ``session_rotated: true``. The
  app adopts the renewed session instead of reloading at its next refresh.
  (#4708)

- Customer purge accepts eligible accounts with completed migration
  metadata, supported legacy creator identifiers or non-live billing
  history. Live subscriptions, unresolved migration state and ambiguous
  ownership still block deletion. In full authentication mode, a retained
  closed account no longer blocks signing up again with the same email
  after customer cleanup. (#4700)

- Customer field-reserialization and organization creator-backfill chores
  no longer overwrite unrelated fields changed since the record was loaded.
  (#4729)

- Colonel account diagnostics stop the per-IP lockout scan after five
  seconds and report an incomplete check rather than timing out on large
  databases. (#4700)

- Signing in after a Colonel session expires returns to the admin
  application instead of a customer-app not-found page. (#4712)

- Confirmation dialogs in Colonel customer, domain and session drawers no
  longer close the drawer and clear the selected record when clicked.
  (#4753)

Security
--------

- Domain-scoped members can no longer use ``scope=domain`` to list another
  domain's receipts, or access the organization-wide receipt list and secret
  activity trail through the ``audit_logs`` entitlement. (#4712)

- Opt-in trusted-provider SSO email linking no longer links an existing
  account when the provider explicitly reports an unverified email or its
  verification claim cannot be read. For GitLab, missing email confirmation
  also prevents automatic linking. See
  ``docs/authentication/per-install-sso.md``. (#4702)

- Full-page navigation validates destinations after URL normalization,
  rejecting paths that normalize into an external-authority form. (#4719)

Documentation
-------------

- Added an operator-approved Entra claim-checking runbook at
  ``docs/runbooks/sso-entra-claim-smoke-test.md``. It distinguishes missing
  email claims from missing mailboxes and records only sanitized claim
  presence and type. (#3499, #4738)

.. _changelog-0.26.15:

0.26.15 — 2026-10-07
====================

Added
-----

- Opt-in ``PUBLIC_HOST_REWRITE`` (``site.network.public_host_rewrite``) for
  proxies that rewrite ``Host`` to the origin target. Mounted applications
  then see the classified public hostname from ``X-Forwarded-Host``.
  It is off by default; see ``docs/operations/proxy-authority-header.md``.
  (#4223, #4623)

- Delivery events for outbound email and webhook notifications, with queue
  hand-off tracked separately from worker results. ``bin/ots notifications
  deliveries`` filters the bounded event feed and shows daily totals with
  ``--counts``. Provider bounces, complaints and suppressions remain on the
  email deliverability pages. (#4479, #4633)

- Implicit TLS/SMTPS delivery with ``SMTP_SSL=true``. This disables STARTTLS
  but does not change the configured port; set the provider's implicit-TLS
  port explicitly, usually ``SMTP_PORT=465``. (#4662)

- Optional file logging alongside the console through the logging config's
  ``destinations`` block, with separate destination levels and formatters.
  File logging is off by default; an unopenable file stops boot. (#4683)

Changed
-------

- Proxies must send one ``X-Forwarded-Host`` value or preserve ``Host``.
  ``Apx-Incoming-Host`` and ``X-Original-Host`` no longer select the public
  hostname; comma-separated ``X-Forwarded-Host`` falls back to ``Host``.
  **Before upgrading**, update proxies that rely on those headers or append
  forwarded hosts. The Colonel host gate still checks conflicting headers.
  See ``docs/operations/proxy-authority-header.md`` and
  ``etc/examples/Caddyfile-example``. (#4384, #4622)

- Forwarded port and scheme headers are now accepted only from trusted
  proxies. **Before upgrading**, configure ``site.network.trusted_proxy``
  for a TLS-terminating proxy connecting from a public address, or set
  ``ASSUME_HTTPS=true``; otherwise requests can appear as HTTP, preventing
  Secure session cookies and producing HTTP authentication URLs.
  ``X-Forwarded-Port`` must contain one port from 1 through 65535.
  Forwarded ``ws`` and ``wss`` schemes normalize to HTTP and HTTPS.
  (#4223, #4623)

- Custom-domain ownership verification is stored in ``ownership_verified``;
  existing ``verified`` values remain readable and the API retains
  ``verified`` as an alias. Rolling back requires copying current values
  back after stopping this version's processes; follow the
  `v0.26.15 rollback procedure <https://docs.onetimesecret.com/en/self-hosting/upgrading-v0-26-15#rollback>`__.
  (#4654)

- Pending tenant SSO sign-ins expire after ten minutes. Sign-ins already
  in progress when this release is deployed must also be restarted.
  (#4610, #4617)

- Canonical-host workspace loading no longer fails when the custom-domain
  index is unavailable. Failed custom-domain lookups are not retried within
  the same request. (#4220, #4620, #4670)

- Authentication routes consistently return a domain-unavailable ``503``
  when the custom-domain record cannot be read. Starting SSO returns to
  sign-in with that message instead of redirecting to an identity provider.
  (#4668, #4675)

- Archived organizations are no longer selected through
  ``O-Organization-ID``, remembered workspace selection or a custom domain;
  organization loading falls back to the default workspace. (#4565, #4661)

- Failed email deliveries can be retried through the dead-letter queue
  instead of being skipped as duplicates. **Duplicate emails are possible**
  if a provider accepted a message before reporting an error, or automatic
  replay cannot confirm publication or complete acknowledgement. (#4479)

- Invalid email payloads and queue messages with invalid JSON, a non-object
  body or an unsupported schema version go to the dead-letter queue rather
  than being dropped or left unacknowledged. The automatic auth-email DLQ
  job still discards malformed messages that cannot identify an original
  queue. (#4479)

- Region and jurisdiction icons now depict the selected region rather than
  its continent. Explicitly configured jurisdiction icons are unchanged.
  (#4626)

Removed
-------

- The development-only ``DOMAIN_CONTEXT_ENABLED`` and ``DOMAIN_CONTEXT``
  variables, ``development.domain_context_enabled`` config key and
  ``O-Domain-Context`` header. Remove them from local setups and use the
  custom domain as the request host instead. (#4220, #4621)

Fixed
-----

- Workspace selection survives page reloads, direct URL navigation and a
  reload overtaking the selection request. The switcher stays available
  after selecting a workspace the user does not own, and settings links
  appear only for owners and admins. (#4565, #4661)

- Organization invitations send admins to settings and members to the
  dashboard. Role-guard redirects now explain the required access or that
  access could not be confirmed, without replacing an existing notice.
  (#4566, #4659, #4667)

- Pages whose application bundle never starts show a reload/support notice
  after 30 seconds instead of spinning indefinitely. Bundle download or
  startup failures show the failure notice immediately. (#4596, #4666)

- Email delivery events distinguish skipped or log-only delivery from sent
  mail. Email-change delivery status also reports ``skipped`` when no message
  was dispatched. Mail modes with surrounding whitespace select the intended
  transport. (#4479, #4643, #4644)

- Rejected queue messages no longer remain unacknowledged, and concurrent
  processing no longer mixes message identifiers or schema checks. Invalid
  email templates are not retried; favicon timeouts can be retried once.
  (#4479, #4644)

- Manual CLI and Colonel DLQ replay no longer skips messages as duplicates.
  Failed messages stay queued; an unconfirmed commit stops replay and
  reports an unknown outcome. See ``lib/onetime/jobs/README.md`` for retry
  behavior and duplicate-delivery risks. (#4479, #4644)

- Automatic auth-email DLQ replay retains messages when replay fails or the
  destination queue is missing, and progresses past deferred messages
  instead of blocking each batch. Messages marked replayed by the previous
  version wait at most an hour before retry. See
  ``lib/onetime/jobs/README.md`` for recovery behavior and duplicate-delivery
  risks. (#4652, #4653, #4656)

- DLQ listing and lookup visit messages beyond the first without repeating
  it. Inspection retains messages but may change their order. (#4650, #4651)

- Organization entitlement changes propagate to existing memberships;
  partial updates report affected memberships and reconciliation guidance.
  (#4655)

- Unlimited plan limits no longer become zero when imported or read from
  cached ``Infinity`` values. (#4655)

- Blank mail settings no longer prevent provider-specific environment
  credentials from being used. Amazon SES falls back to ``AWS_REGION``
  rather than treating the default transport placeholder as a region.
  Synchronous email delivery preserves the recipient's locale. (#4655)

- With background jobs disabled, sender-domain verification performs the
  provider check and settles its status. An empty DNS-record list no longer
  counts as successful verification. (#4655)

- Account language changes persist across authenticated page navigation.
  (#4655)

- Revealed and burned receipts retain those statuses after the secret's
  expiry instead of appearing expired or expiring soon. (#4655)

- Email addresses accepted by the server, such as
  ``first&last@company.com``, no longer prevent app initialization or
  organization member and invitation lists from loading. (#4655)

- The legacy ``/account/billing_portal`` URL forwards to the
  organization-aware billing portal. (#4655)

- ``ASSUME_HTTPS=true`` remains effective after removing untrusted scheme
  headers. Forwarded hosts containing userinfo are refused instead of
  being misread or falling back to another host. (#4223, #4623)

- Production console backtraces are limited to 20 lines by default.
  ``BACKTRACE_LINES`` changes the limit; ``0`` keeps full backtraces.
  Exception objects, file logs and Sentry reports retain full backtraces.
  Configured logger-category levels, including ``Chores`` and ``CLI``, now
  take effect. (#4683)

Security
--------

- Custom-domain images are validated by content rather than declared MIME
  type. SVG uploads are refused and existing SVG images are no longer
  served; replace affected logos and icons with supported raster images.
  (#4649)

- Authentication emails use tenant links and branding only when the
  recipient's active membership authorizes that domain; otherwise they use
  the canonical host. Raw request hosts are no longer a fallback when no
  verified tenant or configured canonical origin exists. Configure
  ``site.host`` for canonical links; see
  ``docs/operations/proxy-authority-header.md``. (#4648, #4223)

- Domain-limited organization memberships are enforced for every workspace
  selection path, including behind Host-rewriting proxies. Unregistered
  public hosts receive no organization context, and a failed tenant-domain
  lookup does not bypass the scope check. (#4225, #4670, #4672)

- Behind Host-rewriting proxies, origins matching an unclassified public
  host are refused before the application runs. (#4669, #4673)

- Duplicate session cookies are refused before session loading, and cookie
  clears target the public host even behind Host-rewriting proxies. A
  signed-in browser's ``/api/`` requests still require CSRF tokens when an
  ``Authorization: Basic`` header is also present; API-key-only clients are
  unaffected. (#4223)

- Custom-domain sign-up restricted to a domain allowlist refuses sign-ups
  when that list is empty or unreadable instead of allowing every domain.
  (#4655)

- Application request logs redact secret and receipt capability paths,
  including debug traces; lifecycle and receipt-list error logs expose
  fewer identifiers and exception details. External proxy access logs still
  need their own redaction configuration. (#4647)

.. _changelog-0.26.14:

0.26.14 — 2026-09-30
====================

Added
-----

- SAML 2.0 single sign-on for the platform and custom domains, off by
  default. Existing SAML installations must set ``SAML_ENABLED=true``
  before upgrading or SAML sign-in stops. SAML requires a host-only,
  Secure session cookie with ``SameSite=Lax`` or ``None``; IdP-initiated
  sign-in and single logout are not supported. See
  ``docs/authentication/per-install-sso.md``,
  ``docs/authentication/per-domain-sso.md`` and
  ``docs/authentication/saml-policy.md`` for setup and supported options.
  (#4450, #4604)

- Domain refresh can use spare batch capacity to recheck recently added,
  edited or checked domains that remain unverified or unresolved.
  ``jobs.domain_refresh.dns_propagation_window`` defaults to ``24h``;
  set it to ``'0'`` to disable.

- Added a dry-run-first housekeeping chore to remove orphaned Approximated
  virtual hosts after changing validation strategy. Switching strategies
  does not remove these billable hosts. See
  ``lib/onetime/domain_validation/README.md`` for cutover prerequisites,
  cleanup commands and deletion safeguards.

- Successful ``POST /auth/create-account`` responses now include
  ``next_action``: ``verify_email`` when email verification is required,
  or ``sign_in`` when the account can sign in immediately. #4576

- Credential rejection responses now include ``code`` and ``code_scope``
  fields, with ``code_scope`` set to ``credential``. These distinguish
  invalid or suspended credentials, invalid API keys, and locked or
  unverified accounts. #4469

Changed
-------

- Unusable platform SAML settings no longer prevent per-domain SAML routes
  from registering when organization SSO is enabled. The misconfigured
  platform provider stays hidden. (#4450)

- An SSO ``email_verified`` claim containing any ``false`` value now leaves
  the account unverified, including array-valued SAML attributes. (#4450)

- Domain refresh now checks all custom domains in pages of ``batch_size``
  instead of repeatedly checking only the newest batch. See
  ``lib/onetime/domain_validation/README.md`` for refresh timing,
  scheduler requirements and capacity tuning.

- Custom-domain verification feedback, API responses, CLI output and logs
  now distinguish failed, indeterminate, expired and overridden checks
  from successful verification.

- ``caddy_on_demand`` now requires a matching TXT challenge to verify
  custom-domain ownership. Existing domains without that record lose
  verification when checked, preventing new certificate authorization and
  features that require verification, including SSO. Publish the TXT record
  shown on the domain verification page or configure a Colonel override
  before upgrading. Without scheduled refresh, run
  ``bin/ots domains verify --all`` after upgrading and periodically
  thereafter. See ``lib/onetime/domain_validation/README.md`` for upgrade
  and strategy-cutover guidance.

- ``caddy_on_demand`` now reports DNS resolution and TLS certificate status.
  The application host needs outbound DNS and TCP 443 access to custom
  domains. See ``lib/onetime/domain_validation/README.md`` for probe
  limitations and network troubleshooting.

- Verified domains with indeterminate TXT checks now lose verification if
  another check is still indeterminate after a seven-day confirmation
  window. The window starts with the first indeterminate check; Colonel
  overrides are exempt. Never-confirmed domains under ``caddy_on_demand``
  can lose verification on their first check. See
  ``lib/onetime/domain_validation/README.md`` for confirmation rules.

- Bulk domain verification now uses strategy-specific pacing: 0.5 seconds
  for ``approximated``, no pause for ``caddy_on_demand`` or ``passthrough``.
  Explicit ``jobs.domain_refresh.rate_limit`` or CLI ``--rate-limit`` values
  still override this, including an existing ``rate_limit: 0.5`` setting.

- Install-wide OIDC sign-in now reports ``sso_issuer_mismatch`` when
  ``OIDC_ISSUER`` does not exactly match the discovery document's issuer.
  Per-domain Test Connection reports the configured and discovered issuers
  and rejects discovery documents larger than 256 KiB. See
  ``docs/authentication/per-install-sso.md`` for troubleshooting. #4513

- Full authentication mode requires auth-database migration 011 for
  remembered sessions. It runs automatically at web-process boot; installs
  applying auth migrations manually must apply it before starting this
  version or session verification fails.

- Familia migration execution now checks dependencies and records successful
  single-migration runs as well as batch runs. Failed or partial runs exit
  non-zero without being marked applied. Applying or rolling back requires
  ``--run``; use ``--dry-run`` to preview pending migrations. See
  ``docs/development/data-migrations.md`` for commands and boot-time
  migration caveats.

- Duplicate session cookies are rejected with ``403`` and cleared by
  default, requiring a fresh session. Set
  ``MIDDLEWARE_COOKIE_TOSSING=false`` to disable this protection.

- Session-verification outages now return ``503`` with ``Retry-After: 5``
  instead of ``401``, without ending the session. Coded ``401`` responses
  now include a ``WWW-Authenticate`` challenge. Update outage alerts that
  count ``401`` responses and ensure intermediaries preserve origin ``503``
  bodies. See ``docs/authentication/session-consistency-rollout.md``.
  (#4469)

- Signed-in sessions now have a default 30-day absolute lifetime in both
  authentication modes, regardless of activity. Remembered sessions expire
  sooner, after 14 days. Configure ``SESSION_ABSOLUTE_TIMEOUT`` in seconds;
  ``0`` disables the absolute bound.

Removed
-------

- Removed the response-header isolation middleware in favor of Otto 2.11's
  per-request error responses, preserving protection against session-cookie
  leaks. The ``otto`` dependency now requires ``~> 2.11``. (#4547)

- Removed ``had_valid_session`` from ``GET /bootstrap/me`` and page
  hydration. Clients must use ``auth_status`` instead; session-verification
  outages are reported as ``auth_status: "unavailable"``. (#4468)

Fixed
-----

- Approximated DNS lookup failures no longer immediately revoke custom-domain
  verification. The application falls back to its own DNS resolver, retaining
  existing verification within the confirmation window when the result
  remains indeterminate. An unknown Approximated status also no longer
  clears stored resolving status. See
  ``lib/onetime/domain_validation/README.md`` for fallback rules.

- Colonel verification overrides now survive subsequent failed checks until
  removed by an operator or replaced by successful TXT verification.

- Custom-domain pages under ``caddy_on_demand`` now show TXT setup,
  verification controls and DNS targets for this installation rather than
  Approximated proxy targets. Status badges distinguish pending verification,
  pending certificates and unknown SSL status.

- Newly added custom domains now receive their first check when the
  verification page opens under ``approximated`` and ``caddy_on_demand``.

- Unicode and equivalent punycode names now identify the same registered
  custom domain for incoming requests and certificate authorization. The
  alternate spelling can no longer be registered as a separate domain.

- Domain validation strategy aliases and mixed-case settings now produce
  canonical strategy names in frontend payloads, so domain pages show the
  correct setup and verification controls.

- "Remember me" now gives sign-ins a fixed 14-day session lifetime in both
  authentication modes, subject to shorter configured session limits.
  Remembered sessions appear on the sessions page and remain revocable.
  ``AUTH_REMEMBER_ME_ENABLED=false`` disables the feature.

- Fixed SSO and transactional email URLs behind proxies that send a doubled
  ``Host`` header. URLs now use the verified custom domain or a configured
  canonical host, including its configured non-default port. (#4517, #4499)

- Custom-domain SSO is now available only while ownership is verified,
  including callbacks for sign-ins started before verification expired.
  SSO settings still show callback URLs and SAML identifiers so the provider
  can be configured before verification. #4579

- In full mode with ``AUTH_VERIFY_ACCOUNT_ENABLED=false``, web signup no
  longer fails with "logins do not match" and sends new accounts to sign-in.
  #4572, #4576

- In simple mode, signup with automatic email verification now sends new
  accounts to sign-in instead of prompting for an email that is never sent.
  #4576

- Selected plans and internal redirects now carry through sign-in after
  signup. #4576

- Completing second-factor authentication in full mode now rotates the
  session ID. Sign-in is refused if the old session cannot be ended.

- SQLite URL redaction now preserves file paths containing ``:`` or ``@``
  and displays ``sqlite::memory:`` correctly. (#4450)

Security
--------

- Platform SAML is restricted to its configured platform host, even when
  platform SSO fallback is enabled. Custom domains must configure their own
  SAML provider; remove their ACS registrations from the platform IdP. See
  ``docs/authentication/per-install-sso.md``. (#4450)

- The example Caddy configuration removes query strings and redirect locations
  from logs. Apply equivalent filtering to deployed ingress logs when enabling
  SAML; see ``docs/authentication/saml-callback-transport.md``. (#4450)

- Pinned ``ruby-saml`` to an exact version and added dependency-advisory
  checks to pull requests. (#4450)

- SSO failure diagnostics are limited to bounded, single-line messages,
  preventing identity-provider response text from forging or flooding
  authentication log lines. (#4450)

- Semantic Logger now redacts URI credentials and whole query strings from
  supported log-event fields across all appenders. Ordinary query parameters
  are also removed; email addresses remain unchanged. See
  ``lib/onetime/log_scrubber.rb`` for coverage and limits. Direct
  stdout/stderr output and Sentry reports use separate paths.

- ``bin/ots status`` now masks query strings in SQLite
  ``AUTH_DATABASE_URL`` values instead of printing them in full. (#4450)

Documentation
-------------

- Added platform and per-domain SAML setup guides and provider-registration
  guidance. See ``docs/authentication/per-install-sso.md`` and
  ``docs/authentication/per-domain-sso.md``. (#4450)

- Corrected ``apps/internal/acme/README.md`` to remove the unsupported
  ``check_verification=false`` parameter.

- Added ``docs/development/data-migrations.md`` to explain migration and
  maintenance mechanisms, migration state and record-write behavior.

.. _changelog-0.26.13:

0.26.13 — 2026-09-22
====================

Added
-----

- Signed-in organization members can connect an existing account to their
  custom domain's SSO provider from Connected Identities after re-authenticating
  on that domain. No operator configuration is required. (#3849, #4427)

- JSON ``401`` responses for refused sessions now include stable ``code`` and
  ``code_scope`` fields. #4462
- Clients can mark timer-driven ``GET`` and ``HEAD`` requests with
  ``X-Session-Activity: passive`` so they do not extend the inactivity deadline.
  #4455

- Full authentication mode now supports Sign in with Apple for platform
  accounts, but not custom-domain SSO. See the Apple setup and session-cookie
  requirements in ``docs/authentication/per-install-sso.md``. #4447

Changed
-------

- Idle dashboard tabs now sign out at the configured inactivity deadline;
  background refreshes and refused requests no longer keep sessions active.
  #4455
- Tabs reload once and show a message when a session ends, is revoked, or is
  replaced elsewhere. Unsaved secrets receive a navigation warning. #4464, #4465
- Session logs now use ``session_handle`` instead of ``session_id`` and omit
  ``redis_key``. Update affected log queries, alerts, and dashboards. #4461
- Authentication and otherwise uncached API responses now send
  ``Cache-Control: private, no-store``. #4461, #4470
- Deploy this release's backend and frontend together. Mixed versions can
  temporarily degrade session handling. See
  ``docs/authentication/session-consistency-rollout.md``. #4463

- Colonel now rejects malformed related passkey origins and origins owned by
  another organization with a field-specific validation error. Enter complete
  origins such as ``https://host``, not bare domains. #4421

- Ordinary duplicate sign-ups now log
  ``registration_blocked_existing_account`` at info; alerts on
  ``registration_blocked_auth_db_conflict`` now indicate an auth database and
  customer datastore mismatch.

- Diagnostics remain disabled under ``RACK_ENV=test`` unless
  ``DIAGNOSTICS_ENABLED_IN_TEST=true``. Playwright-managed servers also disable
  diagnostics unless ``E2E_DIAGNOSTICS_ENABLED=true``.
- ``bin/ots diagnostics sentry doctor`` now accounts for
  ``DIAGNOSTICS_ENABLED_IN_TEST`` under ``RACK_ENV=test``.

- PostgreSQL deployments whose runtime role cannot alter the auth schema must
  configure ``AUTH_DATABASE_URL_MIGRATIONS`` or apply the passkey migrations
  before upgrading. See ``docs/authentication/per-install-sso.md``. #4414

- Account purges now stop before deletion when an owned workspace retains
  resources or has inconsistent ownership, membership, migration, or contact
  indexes. Resolve reported blockers or run ``ots customers doctor`` before
  retrying. #4440, #4443
- Default-workspace provisioning conflicts now return ``409`` and stop retrying
  on each sign-in. Use ``ots customers diagnose`` to inspect conflicts;
  ``ots customers doctor --repair`` repairs only eligible index conflicts.
  See ``docs/runbooks/ownerless-workspace-email-index-collision.md`` for
  resolution steps. #4443

- Auth0 installations now use the generic OpenID Connect provider. Configure
  the ``OIDC_*`` settings using ``docs/authentication/per-install-sso.md``;
  keep the trailing slash in ``OIDC_ISSUER``. #4512

Deprecated
----------

- The bootstrap field ``had_valid_session`` is deprecated and scheduled for
  removal in #4468. Use ``auth_status`` instead; see
  ``docs/authentication/customer-session-failure-matrix.md``.

Fixed
-----

- ``bin/ots customers doctor --repair`` now preserves deliberately unverified
  SSO customers and reports them for manual verification. #3973

- Colonel organization and billing views now handle numeric subscription period
  end values; missing or malformed values no longer render as invalid dates.

- Logout and session revocation now prevent in-flight requests from restoring
  an ended session or its cookie.
- Repeated session-verification failures no longer sign the user out.
- Colonel now reports ``allowed_signup_domains`` validation errors against the
  correct field.

- The first save of a domain's sign-in configuration now retains its related
  passkey origins. #4421

- A logging failure during an ordinary SSO callback no longer causes the
  sign-in to be rejected as an invalid Connect attempt. #4431

- Concurrent sign-ups using SQLite no longer fail with ``database is locked``.
- ``ots status`` and auth database migrations now accept multi-host PostgreSQL
  URLs.
- ``/auth`` now returns retryable ``503`` responses when the auth database is
  busy or its connection pool is exhausted, instead of a generic ``500``.

- Concurrent and ordinary duplicate sign-ups now return the same response on
  SQLite and PostgreSQL. Responses no longer disclose whether an existing
  account is verified.

- ``pnpm run dev`` now regenerates hydration schemas before starting, preventing
  stale schemas from causing development responses to fail. ``pnpm run
  schemas:rhales:generate`` works again.

- Validation errors in Colonel's domain configuration editor no longer disrupt
  form spacing.

- Opening ``/recent`` directly now loads receipts, and dashboard status refreshes
  now send their scheduled requests.
- Custom-domain lists now reload after signing out or switching accounts in the
  same tab.

- Tabs no longer reload because of unrelated session-snapshot anomalies
  separated by a network failure or a long interval.

Security
--------

- SSO customers remain unverified when their provider rejects email verification
  or the ``email_verified`` claim cannot be read.

- Raw session IDs have been removed from logs because they could be replayed as
  session cookies. Use ``session_handle`` for correlation instead. #4461
- Sessions awaiting a second factor can access only MFA challenge and status
  routes and logout; other protected routes return ``401``. #4453

Documentation
-------------

- Added ``docs/runbooks/sso-accounts-unverified.md`` for detecting and repairing
  unverified SSO customer records after an upgrade.

- Added ``docs/authentication/customer-session-failure-matrix.md`` for session
  refusal behavior and troubleshooting. #4452
- Added ``docs/authentication/session-consistency-rollout.md`` for deployment
  and staging guidance. #4463

- Documented purge preflight behavior in
  ``docs/architecture/deleting-an-account.md`` and added the
  ``ownerless-workspace-email-index-collision`` runbook. #4443

AI Assistance
-------------

- Claude assisted with planning, implementation, review, and browser testing
  for the auth session consistency work in #4451.
- GPT-6.1-Sol for trimming changelog entries


.. _changelog-0.26.12:

0.26.12 — 2026-09-10
====================

Added
-----

- ``RODAUTH_ADMIN_URL`` (config ``site.admin.rodauth_admin_url``): the base URL
  of the standalone Rodauth Admin instance. Optional and credential-free. When
  set in ``full`` authentication mode, the colonel customer page, the customers
  list drawer, and each row of the sessions console link to the matching
  Rodauth account, and the sessions console and per-customer sessions panel
  link to it as the session authority. Nothing is ever requested from it;
  unset renders plain text.

- The admin console shows the running app version (linked to its release
  notes) in the sidebar foot, so operators no longer have to leave the console
  for a workspace page to check it.

Changed
-------

- In ``full`` authentication mode the colonel sessions console and the
  per-customer sessions panel now state that they are not the session
  authority (they read the Redis session store; Rodauth's session table is
  authoritative) instead of presenting a partial list as complete.

- In ``full`` authentication mode, authenticated requests now require the
  authentication database. During an authdb outage, existing browser sessions
  are refused rather than continuing from Redis alone; they work again once
  the authdb recovers.

- Tenant SSO refusals now use distinct error codes for an existing-account
  link that is unavailable on that domain and for a connection started on the
  wrong domain.

- Audit events produced by operations with ``dry_run: true`` now use the same
  envelope as applied operations.

- The active-session inactivity deadline is temporarily extended from 24 to 72
  hours.

Removed
-------

- The development-only ``GET /auth/admin/stats`` stub. Its numbers are served
  by the standalone Rodauth Admin behind real authentication.

- The Organizations list's server-side roster cache and its ``refresh=1``
  bypass. The parameter is still accepted and ignored; the ``details.cache``
  block is no longer sent.

Fixed
-----

- Admin Organization searches and filters no longer load every organization
  and owner. ``pagination.capped`` indicates that a bounded result may be
  incomplete.

- Admin console searches now run only when submitted, rather than while an
  operator types.

- Improved admin sessions, customer, and domain search performance.

- Account deletion from Account Settings now completes reliably.

- Customer search now matches email addresses case-insensitively, including
  legacy mixed-case index entries.

- The Active Sessions card and ``/account/settings/security/sessions`` are
  available when ``AUTH_ACTIVE_SESSIONS_ENABLED`` is set.

Security
--------

- In ``full`` authentication mode, revoking an active session or signing out
  everywhere now blocks the affected browser on its next request.

- Session deadlines in ``full`` mode are now enforced on every request:
  sessions inactive for 72 hours or older than 30 days require sign-in again.

- Accounts created by accepting an invitation now have a visible, revocable
  active session.

- After a revoked session, sign-up and sign-in flows, including SSO, proceed
  as signed-out requests.

- Router fallback ``404`` and ``500`` responses no longer return stale
  response headers.

.. _changelog-0.26.11:

0.26.11 — 2026-09-06
====================

Added
-----

- Colonel now provides a confirmed, reason-required **Impersonate** action on
  the customer detail page. It creates a 30-minute, read-only customer view
  with a persistent banner and a **Stop impersonating** control.

- Impersonation blocks actions that could change data or create customer-facing
  artifacts, including secret, account, billing, and Colonel operations.

- Impersonation starts and normal in-process ends, including expiry, are
  recorded in the operator audit trail.

- Operator audit events are now emitted to the dedicated ``ColonelAudit`` log
  category before storage. Route this category to persistent log collection when
  retention beyond the console's configured caps is required (#4334).

- Added optional syslog delivery for the audit category. Set
  ``LOG_AUDIT_SYSLOG=true`` and configure ``LOG_AUDIT_SYSLOG_URL`` to enable it
  (#4334).

- The Colonel Audit Log can now export its retained, filtered results as CSV or
  NDJSON. ``ots audit list`` provides the same formats for shell workflows
  (#4334).

- Destructive operator actions now accept an optional **reason** for the
  operator audit trail, through the Colonel console, API, and supported CLI
  commands (#4338).

- Added ``ots sessions revoke-all <customer>`` for incident response. It
  revokes tracked customer sessions and Rodauth active-session records, and
  performs a capped best-effort sweep for legacy untracked sessions. A warning
  is shown if that sweep reaches its safety cap (#4354).

Changed
-------

- Reasons remain optional. Blank values are omitted; nonblank values are trimmed
  and stored up to 255 characters. Audit-log readers and exports can view the
  stored text (#4338).

- Failed Colonel sign-ins use a separate 7-day telemetry stream, so attempt
  volume cannot evict destructive-action records from the operator trail
  (#4339).

- With trusted-proxy protection enabled, ``header: Forwarded`` or ``Both`` now
  requires ``mode: depth`` and fails boot in filter mode instead of being
  ignored (#4378).

- In filter mode, ``X-Forwarded-Proto`` from a proxy outside the configured
  trusted CIDRs is ignored. Add the proxy's address range to ``cidrs`` to retain
  forwarded TLS scheme detection (#4378).

- Customer purge now revokes tracked sessions and Rodauth active-session
  records first, with a capped best-effort sweep for legacy untracked sessions
  (#4352).

Removed
-------

- Removed the ineffective ``ots session clean`` command. Use
  ``ots sessions revoke-all`` or ``ots session delete`` instead (#4354).

- Removed the nonfunctional Colonel configuration editor write controls. The
  console configuration view is read-only (#4355).

Fixed
-----

- Simple-mode ``Login failed`` events now identify the attempted account rather
  than the account associated with the request session (#4361).

Security
--------

- Destructive operator actions now report an audit-write failure instead of a
  successful response when their audit event cannot be stored (#4333).
  Because most actions write their audit event after the mutation, operators
  must reconcile the target after such a failure; it may have completed.

- Audit retention trimming can no longer empty the operator trail through the
  audit API (#4334).

- Failed sign-ins against existing Colonel accounts are now recorded as
  ``colonel.signin_failed`` in both authentication modes. The audit event uses
  an obscured account email and coarse failure details (#4339).

- Simple-mode sign-in now authenticates only the account named in the login
  field, including on requests that already carry a session.

- Rack now uses the proxy-configured forwarding header family when resolving
  request authority and scheme, preventing an unmanaged RFC 7239
  ``Forwarded`` header from overriding proxy-managed ``X-Forwarded-*`` values
  (#4377).

- Deployments whose edge sends only ``Forwarded`` must also send
  ``X-Forwarded-*`` headers for TLS scheme detection (#4377).

- With ``site.network.trusted_proxy.enabled: true``, upgraded otto now removes
  forwarded authority headers supplied by an untrusted peer before Rack resolves
  the request host, scheme, or port. Configure trusted proxy CIDRs narrowly
  (#4378).

- RFC 7239 ``Forwarded: host=`` is no longer used to determine the application
  host. Deployments that depend on it must rewrite ``Host`` or provide
  ``X-Forwarded-Host``, ``Apx-Incoming-Host``, or ``X-Original-Host`` through a
  configured trusted proxy (#4121).

AI Assistance
-------------

- AI assistance was used to design the session overlay and its request-path
  restrictions, implement the console action, banner, and audit events, and
  write the accompanying tests.

.. _changelog-0.26.10:

0.26.10 — 2026-08-30
====================

Changed
-------

- v1 API form errors now group by endpoint and are reported at warning level.

- Errors from in-app browsers whose injected bridge did not load are ignored.

Fixed
-----

- Verified signups now retain a validated ``?redirect=`` destination across
  email confirmation, including when the confirmation link opens in another
  browser. A valid pending paid-plan selection still takes precedence (#4305).

- Paid-plan selections made before signup now reach the web-app checkout
  handoff instead of being consumed during email verification (#4305).

- Passkey sign-in now applies the same post-authentication destination rules as
  password sign-in: a valid pending plan selection, then a validated
  ``?redirect=`` destination (#4305).

- Frontend diagnostics now apply configured filtering and grouping to manually
  captured errors.

- Password confirmation flows no longer record a login or run login-session
  side effects.

- Invalid UTF-8 session-cookie values are rejected instead of causing a server
  error.

- Custom-domain lists accept proxy ``vhost.keep_host`` values provided as
  booleans.

- Paid-plan selections made before signup now survive MFA and are consumed only
  after the signed-in user reaches the billing plans flow. A failed handoff can
  be retried during its 24-hour window (#4306).

- ``/billing`` and ``/billing/plans`` now preserve plan-selector query
  parameters when resolving to organization-scoped billing pages (#4306).

Security
--------

- Redirect destinations now accept internal paths only, preventing malformed
  or external targets from crossing the authentication boundary (#4305).

- Authentication logs and diagnostic payloads no longer include redirect-borne
  invitation or email-confirmation credentials (#4305).

- Diagnostic reports no longer include secret or receipt identifiers in event
  grouping keys or request-context paths.

AI Assistance
-------------

- AI assistance was used to trace the redirect drop points across the
  signup, verification, and passwordless sign-in flows, implement the
  server-side persistence with parity validators, and build the
  end-to-end browser coverage.

.. _changelog-0.26.9:

0.26.9 — 2026-08-26
====================

Changed
-------

- Frontend Sentry events now serialize nested extras to depth 6
  (``normalizeDepth``), so schema-validation failures report their
  ``issues[]`` payload instead of ``"[Array]"``.

Fixed
-----

- The API Key settings page no longer breaks for accounts promoted to
  ``admin`` or ``staff`` via ``bin/ots customers role`` (#4298). The
  frontend role enum now mirrors the backend's assignable roles (enforced
  by a contract test against ``SetRole::VALID_ROLES``), and an unknown or
  missing ``role`` degrades to ``customer`` instead of failing the whole
  account record parse.

AI Assistance
-------------

- AI assistance was used to trace the Sentry signatures to the role
  vocabulary mismatch, sync the enums, and add the drift-guard contract
  test.

.. _changelog-0.26.8:

0.26.8 — 2026-08-26
====================

Added
-----

- Legal document URLs are now first-class ``site.legal`` configuration
  (#4281). Set ``TERMS_URL`` and ``PRIVACY_URL`` (and optionally ``DPA_URL``,
  ``COOKIE_URL``, ``AUP_URL``, ``SECURITY_URL``), or configure ``site.legal``
  directly, to render Terms, Privacy Policy, and related documents as links.
  All default to unset: when a URL is unset, the signup/invite consent
  sentence renders the document name as plain text, the branded reveal footer
  drops the link, and the entry is absent from the public footer's legal
  group. These settings are independent of ``footer_links`` — existing Terms
  and Privacy links configured there with explicit ``url:`` values continue to
  work unchanged, and an operator-supplied footer URL takes precedence over
  the default footer configuration.

Removed
-------

- Stripe Payment Link provisioning has been retired. The ``/welcome`` endpoint
  that handled Payment Link redirects now logs the attempt and redirects to
  the homepage; the webhook handler skips Payment Link subscriptions (they
  never carried the ``customer_extid`` metadata the webhook requires). The
  ``bin/ots billing payment-links`` CLI command has been removed entirely.
  Existing Payment Link subscriptions continue to bill normally in Stripe;
  they simply no longer trigger automatic workspace creation. Customers who
  paid via a legacy Payment Link and were not provisioned should contact
  support. Use the Stripe Dashboard to audit or archive any remaining Payment
  Links. (#4212)

Fixed
-----

- Guest-created secrets on branded custom domains now use the domain owner
  organization's lifetime limit (normally 14 or 30 days). The 7-day anonymous
  default remains specific to guest creation on canonical hosts. (#4279)

- Malformed ``multipart/form-data`` requests now receive a ``400 Bad
  Request`` with an explanatory JSON message instead of failing deep in the
  middleware stack (#4283). Previously an empty or truncated multipart body
  raised a 500 from the first middleware that read request params, and a
  multipart Content-Type without a boundary parameter silently produced no
  form fields — surfacing on ``POST /share`` as a misleading "You did not
  provide anything to share". Well-formed multipart requests are unaffected;
  their body is now parsed once, up front, and memoized for the rest of the
  request.

- The frontend locale schema now accepts any well-formed BCP 47 language
  tag (#4284). Previously it capped tags at 5 characters with an
  ``xx``/``xx-XX`` regex, rejecting legitimate values browsers actually
  send — ``en-US-POSIX``, ``zh-Hant-TW``, ``es-419`` — and capturing a
  Sentry error for each. Validation is now delegated to
  ``Intl.getCanonicalLocales`` with a 35-character bound, and a
  malformed visitor locale degrades silently to the supported-locale
  matching and the default locale instead of being reported as an
  application error.

Documentation
-------------

- Documented the canonical-host and custom-domain guest TTL boundaries in the
  API and TTL-policy references.

AI Assistance
-------------

- AI assistance was used to trace the Sentry error signatures to their root
  causes (the custom-domain guest TTL regression, the middleware-level
  multipart parse, and the locale schema length cap), implement the fixes,
  and add regression coverage.

.. _changelog-0.26.7:

0.26.7 — 2026-08-23
====================

Added
-----

- Added integer and float field declarations for Familia models, normalizing
  numeric inputs and legacy scalar values. (#4248)

- Authenticated browser sessions and selected backend error captures now
  carry a pseudonymous actor reference, so operators can correlate an
  issue with the accounts it affects. The backend derives the 16-hex
  ``actor_ref`` from the customer external identifier (extid), publishes
  it to the frontend in the ``diagnostics_ref`` bootstrap payload, and
  attaches it to supported backend captures. No direct identifiers, such
  as email addresses or customer IDs, are sent; however, the reference
  must still be handled as potentially personal data. Anonymous sessions
  and installs without a usable keying secret send no user context, and
  the frontend clears the reference on logout. Existing actor and
  organization references re-key on the deploy that ships this change, so
  a correlation discontinuity of up to the Sentry retention window is
  expected rather than a defect.

Changed
-------

- Custom-domain favicon backoff counters now use native numeric storage.
  (#4248)

Fixed
-----

- Selected frontend Sentry issues use explicit grouping instead of
  minified bundle stack frames. Schema validation errors with a schema
  name group by that name. Axios-shaped request errors with ``config.url``
  group by method, the path normalized by the existing URL scrubbers, and
  an HTTP status or coarse ``aborted``/``network`` outcome; other errors
  retain Sentry's default grouping.

Security
--------

- Passphrase verification on the v2 secret show, reveal, and burn endpoints
  now runs only when ``continue=true``. A metadata-only request
  (``continue`` absent or ``false``) no longer evaluates the supplied
  passphrase, so it cannot be used to test guesses without consuming the
  secret, and it no longer records or clears rate-limit state.
  ``details.correct_passphrase`` has been removed from the v2 secret
  responses; clients should use ``details.show_secret``, which is true only
  when the passphrase was correct and the reveal was committed. The v2
  reveal and burn endpoints now return the same status for a right or wrong
  passphrase when ``continue=false``. The v1 logic classes carry the same
  change for parity; the v1 API was not exposed, since its controller
  always commits (``continue=true``) and never returned the verdict.

.. _changelog-0.26.6:

0.26.6 — 2026-08-20
====================

Added
-----

- Added an opt-in nightly entitlement re-materialization job. Enable
  ``jobs.maintenance.enabled`` and
  ``jobs.maintenance.entitlement_materialize.enabled`` to repair entitlement
  drift from verified Stripe plan data. See
  ``docs/runbooks/entitlement-rematerialization.md``. (#4203)

- Added operator organization deletion through ``bin/ots org delete ORG`` and
  Colonel, with a deletion preview and safeguards for domains, default
  workspaces, subscriptions, and sole-owner organizations.

- Added organization unique-index diagnostics and safe repairs to
  ``bin/ots org doctor``. Use ``--repair`` for missing and stale entries;
  duplicate live values are reported for operator resolution.

- ``SENTRY_FRONTEND_PROJECT`` is an optional repository secret for selecting
  the Sentry project that receives frontend source maps. Set it when that
  project is not ``frontend``; its value must also be included in
  ``SENTRY_PROJECTS``.

- Added the Colonel proxy-header diagnostic at
  ``/api/colonel/system/proxy-headers``. Configure explicit
  ``ADMIN_ALLOWED_HOSTS`` and ``ADMIN_ALLOWED_CIDRS`` before use; see
  ``docs/operations/proxy-header-diagnostic.md``. (#4233)

Changed
-------

- Customer organization deletion now requires cancellation of subscriptions
  that can still bill.

- ``SSO_FORM_ACTION_ORIGINS`` is now only needed for split-endpoint OIDC
  configurations; tenant IdP origins on custom domains are allowed
  automatically.

- Billing-enabled deployments must grant ``audit_logs`` to plans that need
  shared receipt listings, then run ``bin/ots billing catalog sync``.

Fixed
-----

- Organization-doctor output now redacts indexed email addresses.

- Fixed tenant SSO on custom domains being blocked by Content-Security-Policy
  in Chromium.

- Organization deletion now detects custom-domain drift before teardown and
  refuses deletion until attached domains are removed. Repair unrecoverable
  drift with ``bin/ots domains doctor --all --repair``.

- Fixed stale custom-domain ownership after organization transfers. Use
  ``bin/ots domains doctor --all --repair`` to repair existing drift.

- Fixed domain-scoped receipt listings being unavailable to authorized users.

- Fixed Stripe checkout webhooks failing when they race organization creation.

- Fixed Colonel organization-deletion previews reporting domain drift.

- Fixed tenant SSO on custom domains behind proxies that rewrite ``Host``.

- Magic-link, password-reset, account-verification and SSO link-confirmation
  emails now point at the domain the recipient signed in from, instead of the
  canonical host, on deployments behind a proxy that rewrites ``Host``.

- WebAuthn assertions on custom domains are now verified against the domain the
  browser is on.

- CI now extracts frontend build assets from the published image and uploads
  their source maps to Sentry, with preflight and post-upload delivery checks.

- Fixed federated deployments where newly created Stripe subscriptions could
  leave organizations in another region on the free tier until a later
  subscription event. (#4231)

Security
--------

- Customer organization deletion now refuses to delete a default workspace.

- The example Caddyfile now strips client-supplied ``X-Forwarded-Host`` before
  proxying requests.

- ``/api/v2/version`` and ``/api/v3/version`` now require session or Basic Auth.
  Update unauthenticated version probes; anonymous pages and API responses no
  longer expose application or Ruby version details. (#4195)

Documentation
-------------

- Corrected Entra sovereign-cloud SSO guidance. Use an ``oidc`` provider with
  the sovereign v2.0 issuer.

- Documented host handling for deployments with a Host-rewriting proxy in the
  example Caddyfile.

AI Assistance
-------------

- Claude assisted with entitlement re-materialization, configuration, tests,
  and its operator runbook.

- Claude assisted with organization-deletion tooling and coverage.

- Claude assisted with organization-index diagnostics, repair support, and
  coverage.

- Claude assisted with tenant SSO CSP handling and coverage.

- Claude assisted with organization-deletion drift handling and coverage.

- Claude assisted with domain-drift and entitlement fixes.

- Claude assisted with tenant SSO host handling and coverage.

- Claude assisted with public-host resolution for Rodauth-generated URLs and
  regression coverage.

.. _changelog-0.26.5:

0.26.5 — 2026-08-17
====================

Added
-----

- Added configurable link-domain selection through ``LINK_DOMAINS``
  (``features.domains.link_domains``). (#4063)
- Added passkey authentication and credential management behind
  ``AUTH_WEBAUTHN_ENABLED``.
- Social cards can now be disabled with ``BRAND_OG_IMAGE_URL=none``. (#4150)
- Sign-in surfaces can show the country a session came from. Country display on
  the Secret Activity trail is opt-in through
  ``SECRET_ACTIVITY_GEO_COUNTRY_ENABLED``. (#3989)
- Added ``bin/ots customers role reconcile`` to repair customer role-index
  drift. It runs as a dry-run by default; use ``--apply`` to write repairs.
  (#3974)
- Added SMTP2GO as a mail provider (``MAIL_PROVIDER=smtp2go``), including
  sender-domain verification.

Changed
-------

- ``TRUSTED_PROXY_MODE=depth`` now requires an explicit trust-at-edge decision.
  Ensure the origin is reachable only through the proxy tier. (#4024, #4040)
- Colonel now defaults to the canonical ``DEFAULT_DOMAIN``/``HOST``. Configure
  ``ADMIN_ALLOWED_HOSTS`` before upgrading when Colonel uses another host; ``*``
  disables this restriction. (#4062, #4127)
- ``ADMIN_ALLOWED_CIDRS`` allowlists with no valid entries now fail closed.
  (#4062)
- ``GEO_HEADER`` is used only with ``TRUSTED_PROXY_MODE=filter``. Depth-mode
  deployments should use ``GEO_DB_PATH``. (#4024, #4068)
- Renamed ``WEBAUTHN_VERIFY_ACCOUNT`` and ``WEBAUTHN_AUTOFILL`` to
  ``AUTH_WEBAUTHN_VERIFY_ACCOUNT`` and ``AUTH_WEBAUTHN_AUTOFILL``. Update these
  settings before upgrading; the old names are deprecated.
- Custom domains cannot be restricted to passkey-only sign-in.
- Invalid ``TRUSTED_PROXY_MODE`` values now use ``filter`` mode with a warning.
  (#4087)
- Session country API values now contain an ISO 3166-1 alpha-2 code or null.
- Custom-domain sign-in and sign-up are now served only when enabled for that
  domain. Platform SSO is withheld from non-operator hosts when
  ``allow_platform_fallback_for_tenants`` is off. (#4157)
- ``BILLING_ENABLED``, ``STRIPE_AUTOMATIC_TAX`` and ``RABBITMQ_VERIFY_PEER`` now
  accept ``1/true/yes/on/y/t`` and ``0/false/no/off/n/f`` (case-insensitive).
  Invalid values prevent boot; other ``*_ENABLED`` variables are unchanged.

Fixed
-----

- Corrected client-IP selection in ``TRUSTED_PROXY_MODE=depth``. Deployments
  that worked around this issue should restore their actual
  ``TRUSTED_PROXY_DEPTH``. (#4024)
- Fixed forwarded-host parsing and link-domain validation. (#4040, #4063)
- Social cards now use available brand assets, and custom domains no longer
  inherit the install's social image. (#4150)
- Fixed custom-domain ``HttpOrigin`` 403s. (#4170, #4181)
- Fixed full-mode custom-domain sign-in and sign-up routes ignoring per-domain
  opt-in settings; unavailable policy data now returns ``503``. (#4169, #4184,
  #4157)
- Fixed SSO routes returning ``404`` when tenant SSO is available but platform
  SSO prerequisites are unmet. (#4165)
- Fixed SSO-only hosts accepting password and email sign-in requests when their
  per-domain configuration expressed no sign-in preference. (#4167)
- Customers provisioned through SSO are now verified at creation. Use
  ``bin/ots customers doctor --repair`` to repair existing unverified records.
  (#3973)
- The account active-sessions list now shows IP address, browser, and country.
  Existing sessions populate as users re-authenticate. (#3989)
- Fixed custom-domain verification status in workspace and Colonel UIs.
- Improved session-list loading performance in Colonel and customer views.

Security
--------

- V1 API secret creation now enforces the configured anonymous TTL ceiling
  (default 7 days), matching V2. (#4172)
- ``RABBITMQ_VERIFY_PEER`` no longer fails open for values such as ``1``,
  ``yes``, or ``TRUE``. Invalid values now prevent boot.

.. _changelog-0.26.4:

0.26.4 — 2026-08-05
====================

Added
-----

- Added organization Secret Activity, including retention controls and an audit
  events interface. Enable or disable with ``ORGS_AUDIT_LOGS_ENABLED``.
  (#3642, #3975, #3976, #3985, #3992)

Fixed
-----

- Domain configuration is now sanitized and constrained. (#3998)
- Improved sidebar text contrast. (#3994)

Security
--------

- Updated PostCSS to 8.5.23. (#4004)

.. _changelog-0.26.3:

0.26.3 — 2026-08-01
====================

Added
-----

- Added account diagnostics for support and operator tools.

Changed
-------

- Renamed ``PLAN_TTL_ANONYMOUS`` to ``TTL_MAX_ANONYMOUS``; the former remains an
  alias.
- API v3 receipts now return ``recipients`` as ``null`` or an array, and no
  longer include ``custid``.

Fixed
-----

- Restored support for Free plans without a configured price.
- Corrected tenant SSO settings and secret-duration selection.

Security
--------

- Added password-reset rate limits and hardened password reset, invite signup,
  API v2 Basic authentication, and anonymous secret TTL handling. (#3856, #3872)

.. _changelog-0.26.2:

0.26.2 — 2026-07-26
====================

Added
-----

- Added opt-in trusted-email SSO linking for single-tenant deployments.
  (#3836, #3840)
- Expanded operator tools for domains, customers, organizations, and
  entitlements.

Changed
-------

- ``AUTH_ENABLED`` now applies to tenant SSO. (#3672)
- Improved domain repair, organization reconciliation, and email-change
  operations.

Removed
-------

- Removed ``bin/ots domains bulk-repair``; use
  ``domains doctor --all --repair`` instead.

Fixed
-----

- Restored SSO user linking and Chromium SSO redirects. (#3836, #3840, #3848)
- Hardened admin email changes and entitlement-override validation.
  (#3907, #3916)

Security
--------

- Made password-reset requests enumeration-safe and prevented verification
  updates to closed accounts. (#3857, #3916)

.. _changelog-0.26.1:

0.26.1 — 2026-07-21
====================

Added
-----

- Added configurable checkout-host allowlisting for custom domains. (#3821)
- Added brand-pack diagnostics and receipt access telemetry. (#3822, #3825,
  #3829, #3832)

Fixed
-----

- Password changes now invalidate stale sessions. (#3810, #3830)
- Corrected current-plan indicators on the pricing page. (#3824, #3827)

.. _changelog-0.26.0:

0.26.0 — 2026-07-20
====================

Added
-----

- Added a complete favicon and social-sharing icon set, with custom-domain
  overrides and reusable branding presets. (#3048, #3049)
- Added ``BRAND_LOGO_ALT`` for accessible operator-supplied logo text. (#3612)
- Custom domains can use the Incoming Secrets form as their homepage.
- Added receipt access telemetry and organization audit events for secret
  activity. (#3633)

Changed
-------

- Unbranded installs now use the neutral ``Secure Links`` identity and keyhole
  mark; configured branding is unchanged. (#3048, #3049, #3612)
- Brand settings are now centralized under ``brand:``. ``BRAND_LOGO_URL`` also
  controls the masthead logo, and ``BRAND_TOTP_ISSUER`` (defaulting to the
  product name) labels TOTP/MFA entries. Masthead layout knobs live under
  ``site.interface.ui.header.logo`` (``LOGO_LINK``, ``LOGO_SHOW_NAME``,
  ``LOGO_PROMINENT``). (#3612)
- Secret reads no longer change lifecycle state or extend expiration. Receipt
  access is reported through access telemetry instead. (#3633)
- Custom-domain authentication links are hidden by default. Existing domains
  require the following migration to adopt the new setting::

      bin/ots migrate --run 20260703_01_disable_homepage_auth_links

  (#3618)
- Job configuration is now managed through the ``jobs:`` block in
  ``etc/config.yaml``. Per-job ``JOBS_*`` environment variables no longer take
  effect; the deployment-wide switches ``JOBS_ENABLED``, ``JOBS_FALLBACK_SYNC``,
  and ``JOBS_SCHEDULER_ENABLED`` remain env-overridable. (#3775)

Deprecated
----------

- ``SITE_NAME``, ``LOGO_URL``, and ``LOGO_ALT`` (the
  ``site.interface.ui.header.branding`` path) are deprecated in favor of
  ``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``, and ``BRAND_LOGO_ALT``. (#3612)

Removed
-------

- Legacy API v1 responses are JSON-only.

Fixed
-----

- The global authentication kill switch (``AUTH_ENABLED`` / ``AUTH_SIGNIN`` /
  ``AUTH_SIGNUP``) can no longer be bypassed by per-domain configuration.
  (#3453)
- The Content-Security-Policy header is now emitted on web responses by
  default; it was previously gated behind ``CSP_ENABLED=true`` and not sent.
  Set ``CSP_ENABLED=false`` to opt out.
- The API v1 receipt endpoint no longer reveals a concealed (user-supplied)
  secret's plaintext to the creator, matching v2/v3.
- Email delivery failures during synchronous fallback no longer return
  HTTP 500 after the record was persisted; auth and invitation emails stay
  resendable. (#3486)
- Incoming secrets submitted on a custom domain now use that domain for links
  and email delivery.
- Prevented duplicate checkout sessions and subscriptions. (#2605)

Security
--------

- Password-reset responses no longer disclose whether an account exists.
  (#3486)
- Prevented concurrent requests from revealing a burn-after-reading secret more
  than once. (CWE-362)
- Federated subscription benefits are now claimed only after email verification.

.. _changelog-v0.25.11:

v0.25.11 — 2026-06-20
=====================

Fixed
-----

- Normalized secret and receipt lifespans to prevent failures caused by invalid
  stored numeric values. (#3424, #3299)
- SSO sign-in now shows an error when the identity provider does not supply a
  usable email address. (#3478)

.. _changelog-v0.25.10:

v0.25.10 — 2026-06-13
=====================

Added
-----

- Added one-click SSO from disabled homepages when a single SSO provider is the
  only sign-in method. (#3433)

Changed
-------

- Renamed the disabled-homepage ``legacy`` variant to ``closed``. The new name
  is the default; update pinned configuration accordingly. (#3433)

Fixed
-----

- Restored API and dashboard access for records with string-typed numeric
  fields. (#3424, #3268)
- Fixed MFA enrollment QR codes and setup errors. (#3431, #3455)
- Corrected client-IP masking behind trusted proxies. (#3427)
- Burn endpoints now honor ``continue=false``.

Security
--------

- Secret generation now uses cryptographically secure randomness throughout.
  (#3452)

.. _changelog-v0.25.9:

v0.25.9 — 2026-06-09
====================

Added
-----

- Added opt-in ``SIGUSR2``-triggered heap dumps (``HEAP_DUMP_ENABLED``) for
  diagnosing memory growth. Dumps can contain plaintext secrets and must be
  handled as sensitive data. (#3366)

.. _changelog-v0.25.8:

v0.25.8 — 2026-06-06
====================

Added
-----

- Legacy domain-SSO users now automatically adopt their domain organization as
  their default workspace. (#3336)
- Added organization archival and recovery support. (#3336)

Changed
-------

- Updated Familia storage indexes. Existing deployments with legacy indexes
  should run migration ``20260606_01_unique_index_json_to_raw``; boot logs a
  warning with the exact command while any remain. (#3336, #3347)

.. _changelog-v0.25.6:

v0.25.6 — 2026-06-01
====================

Changed
-------

- Consolidated custom-domain incoming-recipient configuration. Missing public
  homepage or API configuration now fails closed. (#3026, #3095)

Removed
-------

- Removed legacy custom-domain recipient endpoints and branding-based public
  homepage/API settings. (#3026, #3095)

Fixed
-----

- Saving domain recipients no longer overwrites existing entries. (#3095)

Deployment
----------

- **Action Required**: migrate existing recipient configuration before resuming
  traffic::

      bin/ots housekeeping run Onetime::CustomDomain migrate_incoming_secrets_to_config

  (#3095)

.. _changelog-v0.25.0:

v0.25.0 — 2026-04-29
====================

Changed
-------

- Invitation acceptance and custom-domain configuration are now atomic,
  improving reliability under concurrent requests. (#2897, #3023)

Fixed
-----

- Added a migration to preserve public homepage settings for existing custom
  domains. (#3023)
- Improved custom-domain deletion, organization lookup, and concurrent domain
  verification. (#3023, #3025)

.. _changelog-v0.24.2:

v0.24.2 — 2026-03-14
====================

Added
-----

- Added configurable locale fallback support via ``fallback_locale`` chains.

Changed
-------

- Expanded locale coverage and promoted all bundled locales to supported status.

Fixed
-----

- Browser language detection now recognizes regional locales. (#2668)

.. _changelog-v0.24.1:

v0.24.1 — 2026-03-12
====================

Changed
-------

- API v1 is frozen for backward compatibility. New functionality targets API
  v2 and v3. (#2615)

Fixed
-----

- Restored API v1 secret and receipt compatibility after the Familia v2 update.

.. _changelog-v0.24.0:

v0.24.0 — 2026-03-05
====================

Added
-----

- Added a unified session and authentication architecture, including migration,
  rollback, and configuration guidance. (#1619, #1673)
- Added CSRF protection, secret-reveal notifications, and dashboard onboarding
  improvements.
- Added dead-letter email replay for authentication-critical messages. Enabled
  by default; set ``JOBS_DLQ_CONSUMER_ENABLED=false`` to disable. (#2530)

Changed
-------

- Unified session management on Redis-backed sessions and modernized API v2
  authentication. (#1619)
- Updated RabbitMQ fallback and dead-letter queue handling.

  Existing installs with pre-existing dead-letter queues must stop workers,
  drain any messages that must be preserved, then run::

      bin/ots queue reset --force
      bin/ots queue init


Removed
-------

- Removed deprecated custom session-management code.

Documentation
-------------

- Added authentication migration and configuration guidance.
