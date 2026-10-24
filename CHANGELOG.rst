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

- Custom domain homepages can limit anonymous secret creation by network:
  an allowed list and a denied list of IPv4/IPv6 addresses or CIDR ranges.
  Visitors in a denied range, or outside every allowed range when any are
  configured, see the domain's private landing page, as if the homepage
  were disabled. Secret links still open from any network, signed-in
  members and management pages are never restricted, and in incoming mode
  ``/incoming`` and the incoming API are not restricted. Both lists are
  empty by default. Edit them in the workspace domain Homepage section,
  ``PUT /api/domains/:extid/homepage-config`` (``allowed_cidrs`` /
  ``denied_cidrs``) or the Colonel domain configs editor. Matching uses the
  trusted-proxy-resolved client address, so behind a reverse proxy it
  depends on ``site.network.trusted_proxy``. (#4757, #4834)

  Editing needs the new ``homepage_network_rules`` entitlement (Identity
  Plus in the example catalog) and the platform flag
  ``ORGS_HOMEPAGE_NETWORK_RULES_UI_ENABLED=true``, off by default; the
  Colonel editor is not gated by the flag. With billing enabled, add the
  entitlement to plans in ``etc/billing.yaml`` and push the catalog. Stored
  rules stay enforced, read-only, after a downgrade or with the flag off.
  With the flag off the API refuses a changed list with 422, and ``DELETE``
  is refused while rules are stored.

- Custom domain sign-up validation can admit the domain's own base domain
  (``secrets.acme.com`` admits ``@acme.com``) with the new
  ``allow_base_domain`` setting, alongside or instead of listed domains. Set
  it on the workspace Signup Validation page, the domain signup-config API
  or the Colonel domain config editor. It needs
  ``ORGS_BASE_DOMAIN_SIGNUP_ENABLED=true`` and the new ``base_domain_signup``
  entitlement, which no plan grants by default (standalone installs grant
  every entitlement). Both are checked at sign-up, so the saved setting
  admits no one while either is missing. If the datastore or plan catalog
  cannot be read, sign-ups not on the explicit list get 503 instead of a
  server error. (#4756)

- Custom domain SAML settings can fill the IdP SSO URL, EntityID and
  signing certificate from the IdP's metadata URL (for Entra, the App
  Federation Metadata Url). The admin picks one of the readable signing
  certificates, shown with its validity window and SHA-256 and SHA-1
  fingerprints, then applies and saves the form, which validates as before.
  The URL is stored as the source of the values; sign-in does not read it.
  ``POST /api/domains/:extid/sso/metadata`` fetches through the same
  outbound guard as OIDC discovery and writes nothing. It allows 30 requests
  per customer per hour (``SSO_METADATA_FETCH_RATE_LIMIT_*``). (#4850)

- ``bin/ots customers prune-closed-accounts`` deletes the closed auth rows
  and audit logs that account closures before this release left behind.
  ``bin/ots customers finish-closures`` purges customer records left by a
  closure that stopped part-way. Both preview by default; add ``--confirm``
  to delete. Run both once after upgrading, ``prune-closed-accounts`` first.
  Outside the shipped containers, export ``AUTHENTICATION_MODE`` before
  ``finish-closures --confirm``, which refuses without it. (#4819, #4830)

- ``bin/ots customers set-default-org CUSTOMER ORG`` and ``bin/ots
  memberships add ORG CUSTOMER --default`` set a member's default
  organization. (#4858)

Changed
-------

- Closing an account in full authentication mode deletes its Rodauth
  ``accounts`` row and every ``account_authentication_audit_logs`` row in
  the same transaction, on PostgreSQL and SQLite. Before, these were kept
  with no expiry, including the plaintext email and the full sign-in
  history (client IP, user agent). Administrative purges and the
  simple-mode delete endpoint delete the same rows. Signing up again with
  the address creates a new, empty account. (#4819)

- A closure interrupted after its auth account was deleted is marked on the
  customer record. ``sync-auth-accounts`` skips it (``Skipped (closing)``),
  ``customers diagnose`` and ``doctor`` report it, and ``doctor --repair``
  clears the marker of a closure that rolled back. A sign-up with that
  address finishes the closure and creates a new customer record; before,
  password sign-up was refused and an SSO or invite sign-up attached the
  new account to the old record. (#4830)

- ``bin/ots organizations`` is the single organization command;
  ``organization`` and ``org`` are aliases. ``--list``, ``--show`` and
  ``--check`` become ``list``, ``show ORG`` and ``doctor --all``, and
  ``add-member`` becomes ``bin/ots memberships add ORG CUSTOMER [--role R]
  [--default]``. ORG arguments accept an extid, objid, ``cus_…``, ``sub_…``
  or custom domain hostname, and customer arguments also accept an objid.
  ``doctor --all`` adds checks for an empty ``owner_id``, a blank display
  name and stale instances-index entries (repairable). Member listings show
  public ids, role, status and an obscured email. (#4858)

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

- Colonel console: tier-1 actions ask for the password before their own
  dialog; a header control elevates ahead of time and shows the countdown;
  an expired admin session can be renewed from the banner by re-entering
  the password; organization detail lists members with Change role and
  Remove; customer detail can set the default organization. The Admin link
  in the user menu opens in the same window. (#4858)

- Rodauth is updated from 2.45 to 2.48 (with Roda 3.108 and Sequel 5.109)
  and comes from the onetimesecret fork. A signed-in session now gets 403
  ``{"error":"Already logged in"}`` from the login, create-account,
  verify-account, email-login, WebAuthn login and unlock-account routes, so
  following a verify or magic link while signed in no longer switches
  accounts. Password reset, and sessions
  the app has not marked authenticated (such as after verify-account
  autologin), are let through. (#4822, #4840)

- The frontend is built in one code-split Vite pass; each lazy route loads
  its own chunk. Production ``script-src`` stays nonce-only: the server
  shell emits a ``csp-nonce`` meta tag and nonced ``modulepreload`` links.
  ``.vite/manifest-admin.json`` is gone. A chunk that fails to load reloads
  the page at most once per tab per minute (the ADR-046 bound); one that
  keeps failing fails its navigation and shows a notice with a reload
  button. The page never reloads itself while a revealed secret, a receipt's
  one-time generated value or fresh MFA recovery codes are on screen.
  (#4846)

- Locale messages load on demand. English ships in the entry bundle; each
  other language is a chunk fetched before the app mounts or before a
  switch applies. ``?locale=`` now applies on signed-in pages for the
  browser session and is never saved to the account. ``<html lang>`` uses
  BCP 47 tags (``pt-BR``) and, like the page title, follows switches. A
  locale the build has no messages for is not offered. If a language chunk
  fails on first load, the page opens in the default language, or English,
  with a notice. (#4846)

- Receipts whose secret is gone (revealed, burned, expired, orphaned)
  return ``share_path`` and ``share_url`` as ``null`` and omit
  ``secret_identifier`` in receipt and burn responses. A burn whose receipt
  expires or is deleted mid-request returns 404; the secret is still
  destroyed. (#4835)

- A SAML EntityID containing a brace placeholder, such as Entra's
  tenant-wide ``https://sts.windows.net/{tenantid}/``, is refused when a
  domain SSO configuration is saved or tested, and a platform
  ``SAML_IDP_ENTITY_ID`` with one leaves platform SAML off. Sign-in through
  such an EntityID already failed. A configuration saved earlier with one
  can be disabled, but not edited or re-enabled until the EntityID is
  replaced. (#4850)

- The domain signup-config API reports ``uses_allowlist``;
  ``requires_allowlist`` is still sent with the same value but is
  deprecated. A PATCH that sends none of ``validation_strategy``,
  ``allowed_signup_domains`` and ``allow_base_domain`` is no longer refused
  over the stored list. The Colonel domain config editor refuses a change
  that would leave a config invalid; an invalid config can still be
  disabled or repaired. (#4756)

Removed
-------

- The deprecated ``secret_key`` field on ``Receipt`` and ``Secret``, the
  pre-v0.24 name of ``secret_identifier``. Nothing reads it; a stale value
  in a receipt written before the rename is ignored and expires with the
  receipt. No migration is needed. v1 API responses still include
  ``secret_key``, built from ``secret_identifier``. (#4835)

- ``Onetime::Jobs::Publisher.schedule_email`` and the
  ``email.message.schedule`` queue. Once the release runs everywhere,
  delete the durable queue with
  ``rabbitmqctl delete_queue email.message.schedule``
  (``lib/onetime/jobs/queues/maintenance.md``). (#4844)

Fixed
-----

- Expiration warnings are delivered. With the job system they were queued
  on ``email.message.schedule``, which nothing consumed, and were discarded
  unsent. They now go to ``email.message.send`` on the scan that finds the
  secret inside the warning window, so a warning arrives between
  ``warning_hours`` and ``warning_hours`` minus ``check_interval`` before
  expiry. The email names the secret by short id and links to ``/recent``
  on the canonical host, instead of a ``/secret/`` link that always led to
  a not-found page; it carries no receipt or secret identifier. Warnings
  queued by the previous version are rejected as invalid. (#4844)

- A signed-out visit to a page that needs a session redirects to
  ``/signin?redirect=<page>`` and returns there after sign-in. Only a
  same-origin path is accepted, checked on the server and in the app, and a
  POST is never a return path. (#4844)

- In simple authentication mode, opening the emailed verification link
  without a session verifies the account instead of being refused with 422.
  Revealing a verification secret over v1 no longer
  fails with a server error after verifying the account. The reveal
  confirmation form shows its error for secrets without a passphrase and
  keeps its submitting state during the request. (#4831, #4832, #4842)

- Passkey signup (``AUTH_WEBAUTHN_VERIFY_ACCOUNT=true``) with
  ``AUTH_VERIFY_ACCOUNT_ENABLED=false`` marks the customer verified, claims
  a pending federated subscription at verification, sends the branded
  verification email and makes resend available. With
  ``AUTH_MFA_ENABLED=true`` it verifies the account instead of failing with
  a server error: the Rodauth fork (onetimesecret/rodauth#3) adds the new
  passkey's recovery codes to the account being verified and deletes the
  verification key once it is used. (#4829, #4837, #4840)

- ``POST /receipt/{id}/burn`` (v1, v2 and v3, including the ``/private``
  and ``/metadata`` aliases) returns the receipt as it is after the burn
  (``state: burned``). A burn with ``continue=false`` includes
  ``secret_identifier`` under the same rule as ``GET /receipt/{id}``. v1
  ``GET /receipt/{id}`` returns ``metadata_url`` and ``receipt_url`` ending
  in the receipt identifier, no longer writes ``secret_key``, and no longer
  returns a secret key for a revealed, burned, expired or orphaned receipt.
  (#4835)

- Regional fallback chains (``de-AT``, ``fr-CA``, ``pt-BR``) apply in the
  browser, as they already did on the server. (#4846)

- Server-rendered pages preload fewer fonts. Canonical links, ``og:url``
  and ``twitter:url`` carry the page URL without its query string, keeping
  a non-default public port behind a trusted proxy, and ``twitter:domain``
  names the served host, so custom domain pages no longer point social
  scrapers at the install's site. (#4859)

- Secret and receipt pages (``/secret/*``, ``/receipt/*``,
  ``/incoming/:receiptKey``) send ``noindex, nofollow`` and neutral Open
  Graph text, so a pasted link unfurls without naming the page and search
  engines do not list it. (#4859)

Security
--------

- v1 ``GET /receipt/{id}`` and its ``/private`` and ``/metadata`` aliases
  withhold the secret key of a guest-submitted (incoming) secret, as v2 and
  v3 already did. Anyone holding the receipt identifier, including the
  guest who submitted it, could read it. A burn with ``continue=false`` on
  an incoming secret no longer returns the share link that the receipt
  page withholds from its creator. (#4835)

.. _changelog-0.26.18:

0.26.18 — 2026-10-17
====================

Added
-----

- ``bin/ots domains resolve-collisions`` writes a reviewable plan for
  duplicate custom domain records that share one name. The keeper is chosen
  by historical DNS confirmation, then stored ownership verification, then
  use; this is stored evidence, not proof of current DNS control. Ambiguous
  groups and removals with live or unknown billing need ``approved: true``
  in the plan, and ``--yes`` skips only the prompt. Groups whose evidence
  changed since review are skipped. ``--apply --plan`` deletes the
  duplicates' settings and branding without merging them into the kept
  record, and keeps its provider vhost. Stop custom domain writers and
  snapshot the datastore first; see
  ``docs/runbooks/custom-domain-ascii-index-backfill.md``. (#4807)

- Production builds print a self-XSS warning in the browser console.
  (#4804)

Changed
-------

- The custom domain name index is renamed to the ASCII index. The key
  ``custom_domain:canonical_display_domain_index`` becomes
  ``custom_domain:ascii_display_domain_index``, ``bin/ots domains
  backfill-canonical-index`` becomes ``backfill-ascii-index``, doctor
  findings use ``ascii_index_*`` and collision plans use ``ascii_name``.
  Plans from older rule versions are refused; regenerate them. Collision
  reports from ``backfill-ascii-index`` name the record serving each name
  and point to ``resolve-collisions``. (#4807)

  **Before upgrading**, with web, worker and scheduler stopped, preview and
  then apply the rename:
  ``bin/ots migrate migrations/2026-10-15/20261015_01_rename_ascii_display_domain_index.rb``,
  then the same with ``--run``. Started without it, the application sees an
  empty index. Follow ``docs/runbooks/custom-domain-ascii-index-backfill.md``.

- Customer purge commands are renamed; update scripts that call them.
  ``bin/ots customers purge IDENTIFIER`` deletes one account (was
  ``purge-one``, which is gone). ``bin/ots customers purge-inactive
  --older-than DURATION`` is the bulk sweep (was ``purge``); it previews
  unless given ``--purge``, and ``purge --older-than`` is rejected. (#4806)

- Domain removal responses from the CLI (JSON) and the Colonel API drop
  ``reasserts_survivor`` and add ``sender_cleanup``: ``deleted``,
  ``absent``, ``skipped`` or ``failed``. Removal logs carry it and log at
  warn when it failed; ``bin/ots domains remove`` then exits 1. (#4798,
  #4814)

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
  hostname. A concurrent save can no longer recreate a deleted domain.
  (#4798)

- Single-account customer purges sweep the organization, membership and
  domain registries once with pipelined reads, instead of loading every
  record three times during preflight. (#4806)

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
  entering a Secret ID instead of its Value.

- Domain SSO settings show the latest sign-in outcome and failure step,
  retaining the last success alongside later failures. Records expire after
  90 days without a sign-in. Diagnostics and outcomes support all 29 locales.

- ``bin/ots domains backfill-canonical-index`` repairs missing domain-name
  index entries; ``bin/ots domains doctor --all`` reports missing entries
  and duplicate names. For pre-v0.26.14 domains, preview the backfill, then
  apply with the application stopped, following
  ``docs/runbooks/custom-domain-canonical-index-backfill.md``. (#4780)

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
  Colonel override holds it. ``passthrough`` still requires only registration
  to an organization; orphaned records are never served.

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
  earlier repair runs affected indexes, one repair run of the fixed job
  restores them. The job remains off by default.

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

- Guest recent-secret lists no longer persist secret links in browser tab
  storage; existing entries are cleaned on load. After reloading, guests
  copy links from the receipt page instead. (RISK-2026-08-14-M10)

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
  ``EMAIL_LOGIN_REQUEST_RATE_LIMIT_*``. Keep the address cap at least twice
  the IP cap and the lockout at least as long as the window.
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

- Customer email-change confirmations, workspace deletions and domain test
  emails use the Colonel security audit sub-trail (newest 1,000, seven days)
  rather than crowding out operator entries. Events are also emitted to the
  ``ColonelAudit`` log stream; longer retention requires external collection.
  Test recipients are obscured. See ``docs/architecture/audit-logging.md``.

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
  organization and records the applied change in the audit log. Organizations
  previously self-archived by tenant SSO are not restored automatically; see
  ``docs/runbooks/sso-self-archived-organization.md`` for the repair procedure.
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
  including /32 and /128. Entries narrower than /24 or /48 were previously
  ignored and now take effect, including ``mode: external`` entries that
  disable the homepage for matching visitors. IP privacy still masks the
  client address seen by the application. (#4056, #4704)

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

- ``bin/ots customers normalize-emails`` previews repairs for previously
  stored mixed-case SSO account emails; ``--confirm`` applies them without
  signing users out, resetting verification or sending mail. Collisions and
  addresses whose Unicode case-folded form differs from their lowercase
  form are left for operator review. Batched runs support ``--limit`` and
  ``--after-id``. Errors cause a nonzero exit; skipped rows also need review
  even when the command exits successfully. ``bin/ots customers doctor``
  reports these mismatches as ``auth_email_not_canonical``. (#4726, #4731)

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
  verification claim cannot be read. (#4702)

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

- Each request resolves its custom domain once. A failed lookup is not
  retried later in the same request. Canonical-host organization loading
  no longer depends on the custom-domain index. (#4220, #4620, #4670)

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

- Queue workers settle every rejected message and keep message identifiers
  and schema checks separate during concurrent processing. Invalid email
  templates are not retried, and favicon timeouts can be retried once rather
  than skipped as duplicates. (#4479, #4644)

- Manual CLI and Colonel DLQ replay release idempotency claims before
  republishing and commit republish and removal together. Failed messages
  remain in the queue; an unconfirmed commit stops the replay and reports
  an unknown outcome. (#4479, #4644)

- Automatic auth-email DLQ replay retains messages when claim release,
  publication or processing fails, or the destination queue no longer
  exists. It commits publication before removing the message, records
  completed replay to avoid immediate duplicate publication, and does not
  reconnect midway through a batch. Messages marked replayed by the previous
  version wait at most an hour before retry. (#4652, #4653, #4656)

- Automatic DLQ replay progresses past held or unroutable messages instead
  of letting them consume each batch. Runs have a 240-second time budget;
  held messages remain queued for later runs. (#4656)

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
  including debug traces. Lifecycle logs use shortened identifiers and
  receipt-list errors omit raw exception messages. External proxy access
  logs still need their own redaction configuration. (#4647)

.. _changelog-0.26.14:

0.26.14 — 2026-09-30
====================

Added
-----

- SAML 2.0 single sign-on for the platform and custom domains, with an RSA
  signing certificate, configurable NameID policy, and per-domain callback
  origins. Secure session cookies may use ``SameSite=Lax`` or ``None``;
  IdP-initiated sign-in and single logout are not supported. See
  ``docs/authentication/per-install-sso.md`` and ``per-domain-sso.md`` for
  setup, and ``saml-policy.md`` for interoperability options. (#4450)

- SAML is off unless ``SAML_ENABLED`` is ``true``, one switch for the
  platform and every custom domain. While it is off, no SAML route is
  registered, the SAML callback answers ``404``, no SAML sign-in button is
  shown, and the domain SSO API refuses to save or edit a SAML
  configuration (disabling or deleting one still works). Saved
  configurations are kept and resume when it is turned back on. A custom
  domain restricted to SSO that uses SAML has no sign-in method while it is
  off. Other SSO providers are unaffected. An unrecognized value fails boot.
  (#4604)

- ``jobs.domain_refresh.dns_propagation_window`` (default ``24h``). Custom
  domains that are not yet verified or not yet resolving, and were added,
  edited or checked within this window, fill any room the regular page leaves
  under ``batch_size`` on each domain refresh run, so a new domain can be
  re-checked before a full walk of the domain set completes. Set it to
  ``'0'`` to disable.

- ``remove_orphaned_approximated_vhosts`` housekeeping chore, for installs
  that moved from the ``approximated`` validation strategy to another one.
  Changing the strategy deletes nothing on Approximated, so each domain keeps
  a billable virtual host there and the old vhost data on its record; the
  chore removes both. It is a dry run by default: it lists the deletion
  candidates and makes no Approximated API call. When the housekeeping job is
  enabled (``jobs.maintenance.enabled`` and
  ``jobs.maintenance.housekeeping.enabled``, both off by default), it also
  runs the chore nightly, as a dry run unless
  ``APPROXIMATED_VHOST_CLEANUP=apply`` is set in the scheduler's environment.
  To delete, run it with the variable set::

      # Dry run (default)
      bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts

      # Apply
      APPROXIMATED_VHOST_CLEANUP=apply bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts

  Only the literal value ``apply`` deletes. Keep ``approximated.api_key`` and
  ``proxy_ip`` / ``proxy_host`` configured after the cutover: the chore needs
  the key to delete and the proxy address to tell which domains still point
  at the Approximated cluster. A virtual host is deleted only when the domain
  resolves to addresses outside the cluster and Approximated reports it as
  not resolving and not receiving traffic; everything else is skipped and
  picked up on a later run. ``verified``, ``resolving`` and the TXT fields
  are never changed. Details are in ``lib/onetime/domain_validation/README.md``.

- Successful ``POST /auth/create-account`` responses now include
  ``next_action``: ``verify_email`` when the emailed link must be followed
  before signing in, ``sign_in`` when the new account can sign in at once.
  #4576

- JSON responses that reject a login, password, passkey, second factor,
  re-authentication or API key now include the ``code`` and ``code_scope``
  fields that refused sessions gained in 0.26.13, with ``code_scope`` set to
  ``credential``. A ``401`` carries ``invalid_credentials``,
  ``api_key_invalid`` or ``suspended_credentials``; the ``403`` for a sign-in
  to a locked or unverified account carries ``account_locked`` or
  ``account_unverified``. #4469

Changed
-------

- When org-level SSO is enabled and the platform ``SAML_*`` variables are
  present but unusable, the ``saml`` route is now registered as the tenant
  placeholder, as if the variables were absent, instead of not at all; the
  platform SAML button stays hidden. A platform-side typo can no longer
  remove the route that per-domain SAML injects into. (#4450)

- The SSO ``email_verified`` hold now recognises an array-valued claim, which
  is how SAML attributes arrive: any ``false`` among the values leaves the
  account unverified with an ``idp_unverified`` hold. (#4450)

- The domain refresh job now walks the whole set of custom domains, one page
  of ``batch_size`` per run, instead of refreshing the newest ``batch_size``
  domains on every run. The page is derived from the clock and
  ``check_interval``, so nothing is stored between runs. On installs with
  more domains than ``batch_size``, every domain is now refreshed once per
  walk (number of pages times ``check_interval``); a skipped run costs its
  page one extra walk.

- Verify results distinguish "could not tell" from "no". The Colonel verify
  response gains ``details.dns_indeterminate``, ``details.dns_message`` and
  ``details.dns_outcome`` (``validated``, ``indeterminate``,
  ``confirmation_expired``, ``override_held`` or ``failed``); the
  ``domain.verify`` audit event detail carries the same fields.
  ``bin/ots domains verify`` prints ``indeterminate`` and ``no (override)``
  in place of yes/no, adds
  ``Indeterminate`` and ``Demoted`` counts to the bulk summary
  (``indeterminate_count`` and ``demoted_count`` in JSON, plus
  ``issue_details.dns_indeterminate``), and the domain refresh summary line
  and a warning log line report both, so a domain that lost verified status
  can be found without a console session.
  Re-verify in the Colonel domain toolbox now reports the outcome of the
  check, as the domain list and detail pages do, instead of announcing every
  completed call as a success.

- The ``caddy_on_demand`` domain validation strategy now checks the domain's
  TXT challenge record before a custom domain counts as verified. Previously
  every verify pass under this strategy marked the domain verified without a
  DNS check. The rule is the same one the ``approximated`` strategy applies:
  exactly one TXT value at the validation record, equal to the challenge. The
  application performs the lookup itself, so it needs a working system
  resolver. An internationalised hostname is looked up in its punycode form.
  Caddy obtaining a certificate is not treated as proof of
  ownership; the internal ACME endpoint continues to authorise certificates
  only for verified domains.

  **Upgrade note for self-hosted installs using** ``caddy_on_demand``: a
  domain that was marked verified without its TXT record loses verified status
  the first time it is checked after upgrading. While unverified, the ACME
  endpoint refuses new certificates for it, features that require a verified
  domain (link creation under ``features.domains.require_verified`` and SSO)
  stop working for it, and its authentication emails link to the canonical
  host. To keep a domain verified, either publish its TXT record or set the
  verification override for that domain in the Colonel admin; an override
  holds verified through failed checks until it is removed or a check passes.
  The record's host and value are shown to the domain's owner on the domain's
  verification page (see the next entry), on the Colonel domain detail page,
  in the output of ``bin/ots domains verify <domain>``, and as
  ``txt_validation_host`` / ``txt_validation_value`` in the domains API
  payload.

- The customer-facing domain pages now work under ``caddy_on_demand``. They
  previously showed the TXT challenge record, the status badge and the verify
  button only under ``approximated``, so under ``caddy_on_demand`` a customer
  had no way to learn which TXT record to publish. Both strategies now get
  the verification page: the TXT record's host and value, the verify button,
  and the status badge in the domain list and header. Adding a domain lands
  on that page, which runs the first check when it opens (see Fixed below).
  ``passthrough`` is unchanged and keeps the plain DNS setup page.

  Under ``caddy_on_demand`` the address record on that page points at this
  install: a CNAME (ALIAS/ANAME for an apex domain) to the canonical domain,
  falling back to the site host. The Approximated ``proxy_ip`` /
  ``proxy_host`` values are never shown under this strategy, even when they
  are still configured for the orphaned-vhost chore, and the Approximated DNS
  widget stays ``approximated``-only. The Colonel domain DNS panel shows the
  same address record as the customer pages; it previously showed the
  Approximated proxy targets under every strategy.

  The status badge has two new readings for the probe's ``PENDING_SSL``
  status (the name resolves, no certificate was seen). A verified domain
  reads "Certificate pending" and is not flagged as a problem: Caddy obtains
  the certificate on the first request after the TXT check passes. A domain
  whose TXT check has not passed reads "Pending Verification" and links to
  the verification page, because no certificate will be issued until it
  does. The same reading now applies, under both ``approximated`` and
  ``caddy_on_demand``, to an unverified domain whose status still says
  active (for example after its TXT record was removed while the certificate
  issued earlier keeps serving): it no longer reads "Active" and no longer
  gets the Manage quick action. "Unverified" is kept for a status check that
  failed.
  The SSL row of the status table reads "Unknown" rather than "Inactive" when
  the check could not tell. Under ``caddy_on_demand`` the table shows when the
  domain was last checked and leaves out the Approximated target address row.

  The verify button's feedback now follows what the TXT check found. The
  response of ``POST /api/domains/:extid/verify`` gains ``details.dns_outcome``
  (``validated``, ``indeterminate``, ``confirmation_expired``, ``failed`` or
  ``override_held``) and ``details.dns_indeterminate``. The success message is
  shown only for a matching record. A lookup that produced no answer says the
  check could not be completed and to try again, and a missing or different
  record says so; before, all three showed the same success message.

  Existing domains are only re-checked when something runs the check.
  Domain refresh runs only in a running ``bin/ots scheduler`` process, with
  ``jobs.domain_refresh.enabled`` on (the default); ``JOBS_ENABLED`` does not
  affect it. The S6 image and the full compose stack start a scheduler; the
  simple compose stack and a plain ``docker run`` do not, and a source
  install runs one only when its Procfile's ``scheduler`` line is enabled.
  Without a scheduler no refresh ever runs: domains marked verified without
  a TXT record then stay verified, and verified on its own still gates link
  creation under ``require_verified`` and SSO. Installs that do not run the
  domain refresh job must run
  ``bin/ots domains verify --all`` once after upgrading for the TXT check to
  take effect on existing domains, and periodically after that (for example
  from cron) so that a removed record is noticed.

  A lookup that produces no answer (SERVFAIL, REFUSED, timeout) leaves stored
  state alone, within the confirmation window described below. The exception
  is a verified domain that no TXT check has ever confirmed, which is every
  verified domain on this strategy at upgrade: it has no earlier proof to
  protect, so an unanswered lookup also withdraws verified. It becomes
  verified on the next check that finds the record. A Colonel override holds
  it here as well.

  The same applies to a domain verified under ``passthrough``. That strategy
  passes every domain without a DNS check, so its passes are stored in
  verified but are not recorded as a TXT confirmation. If passthrough promotes
  a domain after a definitive check demoted it, the older
  ``verified_confirmed_at`` is cleared with that ended verification lineage.
  After a move from ``passthrough`` to ``caddy_on_demand`` such a domain stays
  verified only once a check finds its TXT record, or under a Colonel override.

- The ``caddy_on_demand`` strategy now reports real resolving and SSL status
  for custom domains. Previously both were always unknown, so the domain
  pages never updated and a domain could not become ready without an operator
  setting ``resolving`` by hand. On each verify or domain refresh the
  application now looks up the domain's A/AAAA records and, if it resolves,
  completes a TLS handshake on port 443 and verifies the certificate for the
  hostname. No request is sent. The check refuses to connect to loopback,
  private, link-local or reserved addresses, and connects only to the address
  it resolved. A DNS lookup that fails on our side (SERVFAIL, timeout)
  leaves stored state unchanged. If the name resolves but the TLS check
  cannot be completed (timeout, no route), ``resolving`` and the probe
  metadata are refreshed while the last SSL observation is kept until its
  certificate expires.

  **Upgrade notes for self-hosted installs using** ``caddy_on_demand``:

  - The application host needs outbound DNS and outbound TCP 443 to the
    custom domains it serves. Without outbound DNS, status stays as it was
    and the domain pages show the last check as failed. Without outbound TCP
    443, ``resolving`` is still updated and the SSL status keeps its last
    observation until that certificate expires; a refused connection reads
    as no SSL.
  - A domain becomes ready (and the internal ACME endpoint starts authorising
    its certificate) once its TXT record verifies and it has an A or AAAA
    record. A domain that stops resolving is no longer ready.
  - A domain with any private or otherwise non-public address among its
    A/AAAA records is reported as resolving with SSL status unknown; the
    probe connects to none of its addresses. A certificate from a private CA
    (for example ``tls internal``) is reported as no SSL, because it does not
    verify against the system trust store.
  - Domains that still carry vhost data from the ``approximated`` strategy
    show it only until a check learns whether the domain resolves. That
    check replaces the Approximated status with the probe's and marks the
    record ``approximated_vhost_pending_cleanup`` for the
    ``remove_orphaned_approximated_vhosts`` chore; the old data stays only
    while every check is inconclusive.
  - With ``jobs.domain_refresh`` enabled, a page of domains that all time out
    takes much longer than before (up to 13s per domain). Refresh runs no
    longer overlap: a tick that fires while the previous run is still working
    is skipped, and its page is picked up on the next walk. Lower
    ``batch_size`` if runs routinely take longer than ``check_interval``.
    The skip works inside one scheduler process. Scheduled jobs assume a
    single ``bin/ots scheduler`` per datastore, which is how the shipped
    compose file and S6 image run it; a second scheduler would repeat every
    refresh.
  - **Cutover from** ``approximated``: removing a domain under
    ``caddy_on_demand`` does not delete anything on Approximated
    (``delete_vhost`` is a no-op for this strategy), and neither does changing
    the strategy. Virtual hosts created while ``approximated`` was active stay
    there, billable and able to serve the hostname, until they are removed on
    the Approximated side: run the ``remove_orphaned_approximated_vhosts``
    chore (see Added above; a dry run unless
    ``APPROXIMATED_VHOST_CLEANUP=apply`` is set) with the Approximated API
    key still configured, or delete them in the Approximated dashboard.

    Sequence the switch so that proven domains keep verified.
    ``verified_confirmed_at`` is new in this version and is only written by a
    passing check on this version, so immediately after upgrading every
    domain has none, including domains Approximated had proven. Before
    changing the strategy: (1) upgrade while still on ``approximated`` and,
    still on ``approximated``, let one full refresh cycle complete on this
    version: either run ``bin/ots domains verify --all`` to the end (without
    ``--dry-run``, which records nothing), or let
    the domain refresh job walk every page (number of domains divided by
    ``batch_size``, times ``check_interval``). Every passing check, whether
    Approximated or the native lookup answered it, stamps
    ``verified_confirmed_at`` for that domain; (2) confirm
    the application host has a working resolver (nameservers in
    ``resolv.conf``, outbound DNS allowed), because ``caddy_on_demand`` is
    the first time the application does the TXT lookup itself on every
    check. If the strategy is switched without this, a first lookup under
    ``caddy_on_demand`` that gets no answer (no nameserver configured, DNS
    egress blocked, SERVFAIL, timeout) withdraws verified from a domain that
    Approximated had proven, and link creation under ``require_verified``
    and SSO stop working for it until the next passing check or a Colonel
    override.

- A verified domain whose TXT checks stop producing an answer is no longer
  held verified indefinitely. The first indeterminate check of a verified
  domain starts a 7-day confirmation window; any definitive answer ends it. If
  a check is still indeterminate once the window has run out, the domain loses
  verified status. The outcome is reported as ``confirmation_expired`` in the
  Colonel verify response, notice and audit event, in ``bin/ots domains verify`` output
  (``Expired`` in the bulk summary, ``confirmation_expired_count`` and
  ``issue_details.dns_expired`` in JSON), in the domain refresh summary line,
  and in a warning log line. The window runs from the first indeterminate
  check, not from the last passing one, so a single failed lookup never
  demotes a domain however long ago it was last checked. The window demotes
  nothing at upgrade: existing domains have no window until their first
  indeterminate check (for ``caddy_on_demand`` see the upgrade note above). A
  Colonel override exempts a domain, and a demoted domain becomes
  verified again on its next passing check. ``CustomDomain`` gains two fields,
  ``verified_confirmed_at`` and ``verified_unconfirmed_since``.

- The pause between domains in a bulk verify now comes from the validation
  strategy: 0.5s under ``approximated`` (its API rate cap), none under
  ``caddy_on_demand`` and ``passthrough``. ``jobs.domain_refresh.rate_limit``
  no longer has a default; leave it unset to use the strategy's pacing, or set
  any number, including 0, to override it. ``bin/ots domains verify --all``
  follows the same rule for ``--rate-limit``. Installs whose config file sets
  ``rate_limit: 0.5`` explicitly keep that pause under every strategy.

- Install-wide OIDC sign-in now stops with the ``sso_issuer_mismatch``
  sign-in error ("Sign-in with this provider is misconfigured. Please contact
  your administrator.") when ``OIDC_ISSUER`` differs from the discovery
  document's ``issuer``, logs both values as
  ``omniauth_install_issuer_mismatch``, and hides the provider from the
  sign-in page in that process for two minutes, after which the next attempt
  checks again (except when sign-in is restricted to SSO). The comparison is
  exact, including any trailing slash. #4513
- Per-domain SSO Test Connection reports ``issuer_mismatch`` with the
  configured and discovered issuers for OIDC, and rejects discovery documents
  larger than 256 KiB. #4513

- Full authentication mode: the auth database gains a nullable
  ``remember_until`` column on ``account_active_session_keys`` (migration
  011). The web process applies it at boot, before it serves requests.
  Installs that apply auth migrations by hand must run it before starting
  this version: the per-request session check reads the column and
  refuses sessions while it is missing. Rodauth's separate remember feature
  is no longer enabled; nothing in the app set or read its cookie.

- ``bin/ots migrate`` now routes every modifying path (batch, single ID or
  file, rollback) through one runner with one invariant: a run is
  dependency-checked, runs the full lifecycle, and is recorded in the
  registry exactly once, only after it succeeds. Single-migration runs are
  now tracked like batch runs. ``--dry-run`` is a real option and previews
  all pending migrations; nothing modifies data without ``--run``, including
  ``--rollback``, which now calls ``prepare`` before ``down`` and removes
  applied state only after a successful actual rollback. A migration that
  returns ``false`` or reports isolated record errors is no longer recorded
  as applied; the run exits non-zero as ``failed`` or ``partial``. An
  already-applied migration is refused for a modifying single run, and an
  ambiguous partial ID is refused instead of picking the first match.

- ``site.middleware.cookie_tossing`` (``MIDDLEWARE_COOKIE_TOSSING``) now
  defaults to on. A request that carries the session cookie more than once,
  as a cookie planted from a sibling or parent host would, is refused with
  ``403`` whichever cookie comes first; the response clears the session
  cookie for the request host and for every parent domain of it, so the one
  refused request removes both the planted cookie and the legitimate one and
  the next request starts a fresh session. The middleware is bound to the
  configured session cookie name and keeps no state between requests (the
  stock rack-protection class remembers a refused request for the life of
  the process). Set ``MIDDLEWARE_COOKIE_TOSSING=false`` to turn it off.

- A protected API or ``/auth`` request whose session could not be verified
  (datastore or auth database unreachable) now answers ``503`` with
  ``Retry-After: 5`` instead of ``401``. The body is unchanged and still
  carries ``code_scope: verification_unavailable``; the session is kept. Every
  coded ``401`` now carries a ``WWW-Authenticate`` challenge:
  ``Session realm="onetimesecret"`` for a session or form credential,
  ``Basic realm="onetimesecret"`` for a rejected ``Authorization`` header.
  Update alerts that counted the outage as a ``401``, and confirm that an
  intermediary in front of the API passes origin ``503`` bodies through. See
  ``docs/authentication/session-consistency-rollout.md``. (#4469)

- Simplified the member count shown on the organization Members tab and
  the checks run when an invitation is created.

Removed
-------

- Removed ``Onetime::Middleware::IsolateResponseHeaders``. Otto 2.11 copies
  router ``not_found`` / ``server_error`` responses per request, which closes
  the same session-cookie leak (#4401). The ``otto`` floor is now ``~> 2.11``.
  (#4547)

- The bootstrap field ``had_valid_session``, deprecated in 0.26.13, is no
  longer sent by ``GET /bootstrap/me`` or in page hydration. Read
  ``auth_status`` instead: the error-recovery case the field described is
  ``auth_status: "unavailable"``. A client from 0.26.13 ignores the missing
  key. (#4468)

Fixed
-----

- Under the ``approximated`` strategy, correctly configured custom domains no
  longer lose verified status when Approximated's DNS checker fails. The
  checker answers ``actual_values: false`` when its own lookup failed; that
  was read as a TXT mismatch and demoted the domain on the next verify or
  refresh run, which in turn disabled the features that require a verified
  domain. Such an answer is now treated as indeterminate: the stored
  verified flag is left alone within the confirmation window, and the
  application tries its own TXT lookup. See
  ``lib/onetime/domain_validation/README.md`` for fallback behavior and the
  confirmation window.

- The same applies to resolving status. An Approximated vhost status of
  ``UNKNOWN`` no longer flips a domain's stored ``resolving`` flag to false.

- A verification override set in the Colonel admin now survives later
  checks. Previously the next verify or refresh run demoted the domain again
  when its TXT check failed, undoing the operator's decision without notice.
  The override is recorded on the domain (``verified_by_override``) and holds
  verified through failed checks until an operator removes it or a TXT check
  passes, at which point DNS holds the flag and the marker is cleared. The
  outcome is reported as ``override_held``.

- Domains beyond the newest ``batch_size`` were never refreshed by the domain
  refresh job, so their resolving and SSL status on the domain pages stayed
  at whatever was last stored. See the change to the job above.

- The first check after adding a custom domain now runs. The verification
  page runs it when it opens for a domain that has not been checked yet,
  under every strategy that checks ownership (``approximated`` and
  ``caddy_on_demand``). Previously the add page scheduled that check two
  seconds after navigating, and navigating away from the add page cancelled
  it, so the page showed no status until the customer clicked Verify. Under
  ``approximated`` the page ran its own check on opening only with the
  ``dns_widget`` feature flag on, which is off by default. A domain that has
  already been checked is not re-checked on opening the page.

- Under the ``approximated`` strategy, an indeterminate provider TXT check now
  falls back to the application's DNS resolver. A matching local answer can
  verify the domain, and a negative local answer keeps a never-verified domain
  unverified. A local negative alone does not revoke an existing
  verification; a definitive negative from Approximated still does.

- Under the ``approximated`` strategy, a TXT check that could not reach
  Approximated at all (no API key configured, a non-200 response, a network
  error) is no longer reported as a failed check. The application does its
  own lookup in those cases too: a matching answer confirms the domain, and
  a definitive negative keeps an unverified domain unverified. For a domain
  that is already verified, a native definitive negative is instead treated
  as indeterminate, retaining verification within the 7-day confirmation
  window. A native lookup that produces no answer is also indeterminate.
  A further indeterminate check after the window expires withdraws
  verification unless a Colonel override holds it. See
  ``lib/onetime/domain_validation/README.md`` for details. An unexpected error
  during a verify is likewise reported as indeterminate rather than failed.

- An internationalised custom domain that was entered in Unicode (for example
  ``bücher.example``) is now found when it is looked up by its punycode form
  (``xn--bcher-kva.example``), and the other way round. Caddy asks the
  internal ACME endpoint about the punycode name and browsers send it in the
  Host header, so such a domain was refused a certificate under
  ``caddy_on_demand`` and was not recognised as a custom domain on incoming
  requests. Stored domains are not changed. The second form of a name that is
  already registered can no longer be added as a separate domain, or reached
  by renaming another one. Only the punycode form that is the encoding of the
  stored name matches it. A name that cannot be converted (an overlong label,
  malformed punycode) is answered with 403 by the ACME endpoint.

- ``features.domains.validation_strategy`` has always accepted any letter case
  and the aliases ``caddy`` and ``external``, but the configured spelling was
  sent to the frontend as written, which only recognises ``approximated``,
  ``caddy_on_demand`` and ``passthrough``. With ``caddy`` the domain pages
  therefore behaved as under ``passthrough`` (no TXT record, no verify
  button). The bootstrap payload and the domains API ``cluster`` now carry the
  canonical name of the strategy in effect.

- The "Remember me" checkbox on the sign-in form now works. It had no
  effect: every session ended after 24 hours without activity whether it
  was ticked or not. A session signed in with it ticked now lasts 14 days
  from sign-in, and activity does not extend it. Revoking the session from
  the sessions page, "sign out everywhere", password changes and logout
  end it exactly as they end any other session. The sessions page marks
  remembered sessions. Two-factor sign-ins are remembered once the second
  factor is completed. Works in both simple and full authentication modes;
  ``AUTH_REMEMBER_ME_ENABLED=false`` still turns it off, and also returns
  sessions already remembered to the default lifetime (their 14-day
  deadline still ends them). The deadline is checked when the session is
  read, so a request that straddles it cannot hand the session a new
  rolling lifetime.
- Every signed-in session now ends 30 days after sign-in, however active it
  is, in both authentication modes. Full mode already held its
  active-session rows to this bound; simple mode had no absolute bound at
  all, so a session used at least once a day never expired. Remembered
  sessions end at 14 days as above; the 30 days is the ceiling for every
  other session. The bound is ``site.session.absolute_timeout``
  (``SESSION_ABSOLUTE_TIMEOUT``), in seconds; ``0`` disables it.

- Fixed SSO and transactional email URLs behind proxies that send a doubled
  ``Host`` header. URLs now use the verified custom domain or a configured
  canonical host, including its configured non-default port, instead of the
  malformed request authority (#4517, reported in #4499).

- Tenant SSO is now offered only after custom-domain ownership is verified.
  Until then, on a domain whose SSO connection is enabled and allowed by its
  sign-in settings, sign-in surfaces offer no SSO, neither the domain's own
  provider nor platform fallback. An SSO request there that reaches the
  sign-in hook, including the return from a sign-in started before
  verification lapsed, stops with the new ``sso_domain_unverified`` sign-in
  error, which says SSO on the domain is not active until it is verified,
  and logs an ``omniauth_tenant_domain_unverified`` event. A SAML response
  posted after verification lapses is answered 404. The domain's SSO
  settings still show the callback URL and SAML identifiers, with a notice
  that SSO there is off until the domain is verified and that verification
  does not change them, so they can be registered at the identity provider
  ahead of time. A domain with no sign-in settings of its own, where SSO is
  the only method, offers no sign-in or signup route until it verifies: its
  SSO routes answer 404, and password signup stays closed there. #4579

- In full mode with ``AUTH_VERIFY_ACCOUNT_ENABLED=false``, signing up from
  the web form no longer fails with "logins do not match", and new accounts
  go to sign-in. #4572, #4576
- In simple mode, when signup does not require email verification
  (``AUTH_AUTOVERIFY=true``, or autoverify in a custom domain's signup
  settings), new accounts now go to sign-in instead of a "Check your email"
  page for an email that is never sent. #4576
- A selected plan and internal redirect carry through sign-in after either
  signup. #4576

- Full authentication mode: completing the second factor now issues a new
  session id, as the password step already did. The old id is ended the way
  a logout ends it, and the signed-in session and its active-session row
  carry across. A sign-in whose old id cannot be ended is refused and the
  user signs in again, so no half-authenticated session is ever left behind.

- URL redaction in logs, the boot banner, the health endpoint and
  ``bin/ots status`` no longer treats a ``:`` or ``@`` in a SQLite file path
  as credentials. The path is shown whole and only the query string is
  masked; the boot banner now shows ``sqlite::memory:`` instead of
  ``****``. (#4450)

Security
--------

- Platform SAML is restricted to its configured platform host, even when
  platform SSO fallback is enabled. Custom domains must configure their own
  SAML provider; remove their ACS registrations from the platform IdP. See
  ``docs/authentication/per-install-sso.md``. (#4450)

- The example Caddy configuration removes query strings and redirect locations
  from logs. Apply equivalent filtering to deployed ingress logs when enabling
  SAML; see ``docs/authentication/saml-callback-transport.md``. (#4450)

- ``ruby-saml`` is pinned exactly in the Gemfile with its advisory history,
  and a ``bundler-audit`` job runs against ``Gemfile.lock`` on every pull
  request. (#4450)

- The SSO failure log line and ``omniauth_failure`` audit event now carry
  the strategy gem's error message bounded to 500 characters on one line,
  for every provider; for SAML the message is a fixed string, and ruby-saml's
  own message is logged separately as ``detail`` on the
  ``[saml_response_refused]`` line, on one line and cut to 200 characters,
  so response text (Issuer, Audience, an unsigned StatusMessage) can no
  longer forge or flood auth log lines. (#4450)

- Semantic Logger output (every appender, including the optional
  ColonelAudit syslog destination) now has the userinfo and the whole query
  string of each URI written with ``://`` replaced with ``***`` in these
  parts of a log event: the message, tags and named tags, the messages of
  the logged exception and its causes, and, inside Hash, Array and Set
  payloads, String, Symbol, URI and Exception values and String, Symbol and
  URI keys. This includes harmless queries, so a logged
  ``https://example.com/list?page=2`` now reads
  ``https://example.com/list?***``. Email addresses are unchanged. Values
  that cannot be scrubbed within fixed limits are replaced with a
  ``[log scrub: ...]`` placeholder, as is text in an encoding that cannot be
  converted to UTF-8 (UTF-7, ISO-2022-JP-2) when its bytes contain a ``:``;
  such text without a ``:`` is left as it is. An event whose scrubbing fails
  is logged as ``[log scrub failed: event withheld]``. Not covered:

  - a query string in text without ``://``, such as a request path
    (``/list?page=2``) or a ``mailto:`` URI
  - other objects in a payload, in tags or named tags, or as the message,
    rendered through ``inspect`` or ``to_s``
  - a ``://`` split by a terminal escape other than an SGR color code or a
    bare ESC (for example ``\e[K`` or an OSC sequence), by a zero-width
    character, or by a backspace
  - Exception payload values whose class defines its own ``to_json`` or
    ``as_json`` (JSON output)
  - exception and cause backtraces (their messages are scrubbed)
  - thread names, and the metric, dimensions and context fields
  - on Semantic Logger 4.x, the logger name, thread name or context set by
    a logging block that returns a Hash
  - values the caller changes after the log call, before the background
    writer formats them
  - output written directly with ``warn`` or to stdout/stderr, and Sentry
    reports

- ``bin/ots status`` now masks the query string of a SQLite
  ``AUTH_DATABASE_URL`` as it already did for other adapters, so a value
  such as ``sqlite://data/auth.db?password=...`` is no longer printed in
  full. A SQLite URL without a query string is shown unchanged. (#4450)

Documentation
-------------

- Operator guides for platform and per-domain SAML
  (``docs/authentication/per-install-sso.md``, ``per-domain-sso.md``), the
  SAML entry in the provider-registration checklist, and ADR-044 recording
  SAML as the reference case for its "OIDC is unavailable" criterion.
  (#4450)

- ``apps/internal/acme/README.md`` no longer documents
  ``check_verification=false``. The ACME ask endpoint has ignored that
  parameter since it was removed from the HTTP interface; the README now
  matches.

- Added ``docs/development/data-migrations.md``, a reference for choosing
  among Familia migrations, ``bin/ots migrations`` backfills, housekeeping
  chores, audit/repair jobs, and Sequel auth-database migrations. It also
  documents migration state, record-write primitives, and the legacy
  read-path tolerances each mechanism is intended to remove.

AI Assistance
-------------

- AI-assisted implementation and regression testing of SAML review fixes. (#4450)

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
