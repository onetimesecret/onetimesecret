# Per-Custom-Domain IP Allowlist (WAF-Style CIDR Filtering)

Status: Draft (proposed) — 2026-07-25
Depends on: Otto v2.6.0 trusted-proxy features; ADR-024 config-resolution semantics

Tenant-configurable CIDR filtering that restricts which networks can reach a
custom domain — an additional access-control layer alongside the existing
per-domain sign-in/sign-up controls. This spec covers (1) the conventional
feature set in comparable SaaS, (2) what Otto provides and where it falls
short, (3) proposed Otto upstream improvements, and (4) the implementation
plan for this repo.

---

## 1. Conventional feature set (SaaS survey, 2025–2026)

Reference implementations surveyed: GitHub Enterprise IP allow lists, Okta
network zones, Atlassian Cloud IP allowlisting, Salesforce login/trusted IP
ranges, Datadog IP allowlist, Cloudflare WAF custom rules, Slack (notable
absence — delegates to the IdP).

### Table stakes (ranked)

1. **CIDR entries, IPv4 and IPv6, with per-entry label/note.** Caps range
   100–500 entries (GitHub, Atlassian 500/app, Okta 150/zone).
2. **Two-phase flow: managing entries ≠ enforcing.** Explicit enable toggle,
   default off (GitHub's deliberate add-then-enable flow).
3. **Self-lockout guard.** Current-IP check at enable time (Datadog requires
   the enabling admin's IP be in the list) and/or an exempt admin surface
   (Atlassian exempts admin.atlassian.com entirely).
4. **Explicit scope contract.** Every vendor documents exactly what is and
   is not covered: UI vs API vs tokens, webhook/integration carve-outs,
   health checks, telemetry (Datadog exempts agent intake).
5. **403 with a human-readable explanation** — never a bare error or a
   redirect loop (Atlassian shows blocked users an explanatory message).
6. **Audit logging of list changes**; at minimum a blocked-request counter.
7. **API management parity** (GraphQL/REST + Terraform where the product is
   API-first).

### Differentiators

- **Monitor/dry-run mode** with would-block reporting (only Cloudflare has a
  true Log action; everyone else ships enforce-only).
- **Step-up instead of block** (Salesforce trusted-IP model: outside the
  range → identity challenge rather than denial).
- **Named reusable zones** shared across policies (Okta, Cloudflare lists).
- **Login-only vs every-request enforcement toggle** (Salesforce).
- **Dynamic zones**: geo, ASN, Tor/VPN classification (Okta enhanced zones).
- **Integration IP auto-registration** (GitHub Apps register their egress
  ranges; orgs opt in to auto-sync).

### Consensus pitfalls vendors warn about

- **Admin lockout** — universally warned, differently mitigated.
- **Trusting X-Forwarded-For** — only Okta models trusted proxies
  explicitly (gateway vs proxy IPs); everyone else uses the connection IP.
- **IPv6 parity lag** — GitHub is still rolling v6 out; dual-stack clients
  flip between address families mid-session, so v4-only lists break users.
- **Integration breakage** — webhooks, OAuth apps, and agents each need a
  documented exemption story.
- **Propagation delay** between save and effect must be stated.

---

## 2. What Otto v2.6.0 provides today

Otto supplies the *inputs* a CIDR filter needs — spoof-resistant client-IP
resolution behind proxies — but no filtering primitive.

### Usable as-is

- **Trusted-proxy config** (`Otto::Security::Config#add_trusted_proxy`,
  `otto-2.6.0/lib/otto/security/config.rb:166`): String/Regexp/Array
  entries; proper `IPAddr` CIDR containment for v4 and v6, parsed once at
  registration; IPv4-mapped v6 folded via `#native`. OTS wires this from
  `site.network.trusted_proxy` YAML in
  `lib/onetime/application/middleware_stack.rb:203-243` (single source of
  truth; `filter` and `depth` modes, mutually exclusive).
- **Client-IP resolution** (`Otto::Utils.resolve_client_ip`,
  `otto-2.6.0/lib/otto/utils.rb:148`): public module function. With no
  trusted-proxy config, or an untrusted peer, forwarded headers are ignored
  entirely (returns `REMOTE_ADDR`). Depth mode
  (`resolve_client_ip_by_depth`, `utils.rb:208`) counts exactly N trusted
  hops from the right with junk positions preserved — not spoofable by XFF
  padding, but assumes origin lockdown.
- **IP privacy middleware** (`IPPrivacyMiddleware`, auto-mounted innermost):
  sets `env['otto.client_ip']` and `env['otto.via_trusted_proxy']`; masks
  IPs, scrubs UA/referer, rewrites forwarded headers.
- **Rejection plumbing**: `raise Otto::ForbiddenError` from anywhere in the
  Otto request chain yields a content-negotiated 403 with security headers
  (`otto-2.6.0/lib/otto/core/error_handler.rb:13`). (Not available to plain
  Rack middleware mounted outside Otto — those return their own tuple, as
  `IPBan` and `AdminNetworkIsolation` already do.)
- **In-gem precedent**: `Otto::CaddyTLS::LocalhostGuard`
  (`otto-2.6.0/lib/otto/caddy_tls/localhost_guard.rb:61`) is the template
  for a path/host-scoped per-request IP filter, including its
  fail-closed-on-unparseable-IP posture.

### Gaps (ranked by impact on this feature)

1. **`env['otto.client_ip']` is the *masked* IP.** Privacy is on by default
   and OTS additionally sets `mask_private_ips = true`
   (`middleware_stack.rb:212`). Default `octet_precision: 1` masks IPv4 to
   an effective **/24** and IPv6 to **/48**
   (`otto-2.6.0/lib/otto/privacy/ip_privacy.rb:38-43`); `/32` allowlist
   entries can never match because the client always arrives as
   `203.0.113.0`. `REMOTE_ADDR` is overwritten with the same masked value.
   This is the binding granularity constraint for the whole feature.
2. **No allow/deny-list primitive.** No `allow_ip`/`deny_ip`, no exposed
   CIDR-set matcher (`Config#trusted_proxy?` is the only one and it is
   single-purpose), no per-route IP policy interpretation.
3. **`filter` mode's XFF walk is leftmost-first and therefore spoofable**
   (`utils.rb:166-172`) unless the proxy tier *replaces* inbound XFF.
   Depth mode is the robust option but permanently disables
   `Request#secure?`'s forwarded-proto trust (modes are mutually
   exclusive, so `otto.via_trusted_proxy` is always false in depth mode).
4. **Geo headers are trusted unconditionally**
   (`otto-2.6.0/lib/otto/privacy/geo_resolver.rb:164-197`): `CF-IPCountry`
   et al. are honored with no trusted-proxy gate, and the built-in range
   table is a toy. Country-based blocking on this foundation would be
   client-spoofable.
5. **Rate limiting is not IP-resolution-aware**: the throttle key is
   Rack::Attack's `request.ip` computed *outside* Otto, so
   `trusted_proxies`/`trusted_proxy_depth` have no effect on it, and
   rack-attack is not a declared dependency.
6. **Ordering footgun**: middleware added via `otto.use` runs *before*
   `IPPrivacyMiddleware` (innermost-pinned) and never sees
   `otto.client_ip`. (For OTS this is moot — we mount at the app's Rack
   stack, downstream of IPPrivacy — but it bites anyone filtering inside
   Otto.)
7. **Error-handler dispatch is exact-class, not ancestry**
   (`error_handler.rb:15`): a custom `IPBlocked < Otto::ForbiddenError`
   falls through to the 500 path unless explicitly registered.
8. **No env-var surface** for proxy/privacy config — code/DSL only.

### Known latent bug this analysis surfaced (file separately)

`AdminNetworkIsolation` accepts arbitrary CIDRs from
`site.admin.allowed_cidrs` including `/32`
(`lib/onetime/middleware/admin_network_isolation.rb:136-145`) and matches
them against the masked IP — entries narrower than /24 (v4) / /48 (v6)
silently never match. Its doc comment even suggests office-VPN CIDRs.

---

## 3. What Otto could provide (upstream proposals)

Per the prior repo decision (`0622-otto-homepage-matching-cidrs-CONSIDER.txt`):
policy stays in OTS; Otto should grow small, reusable primitives.

Otto's privacy-by-default frame is right for a public open-source project,
but private/compliance deployments invert the priority: granular
auditability supersedes. The organizing principle for upstream work is to
separate two axes the current design conflates:

- **Observability posture** — what persists where anyone can see it (env
  keys, logs, fingerprints, error reports). A global invariant; the place
  for discrete, named modes.
- **Policy precision** — what an access-control *decision* may examine,
  ephemerally, at resolution time. A capability; the place for opt-in.

Today the only route to /32 matching is `disable_ip_privacy!` — changing
the observability posture (unmasking logs) to gain a filter. The proposals
below decouple them so precise filtering composes with any posture.

1. **`Otto::Utils.ip_in_cidrs?(ip, cidrs)`** — a public CIDR-set matcher
   with the same parse-once, `#native`-folding, family-aware semantics as
   `trusted_proxy?`. Today the only reuse path is abusing a second
   `Security::Config` instance as a CIDR-set holder.
2. **Named privacy profiles as validated presets** (observability axis):
   `configure_ip_privacy(profile: :anonymous | :masked | :audit)` —
   `:masked` = today's default, `:anonymous` = `enable_full_ip_privacy!`,
   `:audit` = `disable_ip_privacy!` with documented operator retention
   responsibility. Sugar over existing knobs
   (`otto/privacy/core.rb:23-96`), but a declared posture is reviewable
   and validatable — precedent: the mutually-exclusive trusted-proxy modes
   that fail fast on conflict (`PROXY_MODE_CONFLICT_MESSAGE`).
3. **Pre-masking `ip_policy` hook with a verdict-only contract** (precision
   axis): a boot-registered callback invoked inside `IPPrivacyMiddleware`
   after `resolve_client_ip` but before masking, receiving the unmasked IP
   and returning `:allow`/`:deny`/`nil`. The unmasked value exists only in
   the hook's stack frame; env, logs, and fingerprints stay masked. This
   makes /32 filtering "just another opt-in" under any profile —
   `:masked` + hook keeps the privacy posture intact (the configuration
   OTS would run). `octet_precision` cannot substitute: valid values are
   {1, 2} and 1 (= /24) is already the finest.

   An unmasked env key (e.g. `otto.client_ip_unmasked`) is **rejected** as
   an alternative: env is ambient — every middleware, logger, and error
   reporter that serializes it silently joins the privacy trusted base,
   and the privacy-by-default claim stops being checkable. It is also
   unnecessary once the hook exists. Downstream recomputation is not an
   option either: IPPrivacy overwrites `REMOTE_ADDR` and rewrites
   XFF/X-Real-IP to masked values, so the raw material is gone after it
   runs — which is exactly why the hook must live inside it.
4. **Trusted-proxy-gated geo headers** in `GeoResolver` — honor
   `CF-IPCountry` etc. only when `otto.via_trusted_proxy`. Prerequisite
   for any future country-based rules.
5. **Ancestry-aware error-handler lookup**, so
   `class DomainAccessDenied < Otto::ForbiddenError` inherits the 403 path.
6. **First-class `IPFilterMiddleware`** (host- or route-scoped allow/deny,
   fail-closed, `LocalhostGuard`-style) — nice-to-have once 1–3 exist; OTS
   does not need it to ship this feature.

---

## 4. Design for onetimesecret

### Threat model and scope contract

- **Scope: host-scoped, every request.** Enforcement applies to any request
  whose resolved `env['onetime.domain_strategy'] == :custom` and whose
  domain has an enabled access config — HTML, all `/api/*` mounts, secret
  reveal links, and the Roda `/auth` mount (all sit behind the universal
  middleware stack; `/auth` bypasses only Otto's *router*, not the Rack
  stack — `lib/onetime/application/base.rb:165`,
  `apps/web/auth/application.rb:53-61`). Secret links are the primary asset
  being protected, so login-only enforcement is explicitly rejected.
- **Not resource-scoped**: requests on the canonical domain to
  domain-scoped resources (e.g. colonel, workspace domain settings, API
  with tokens) are *not* gated. This is the intrinsic break-glass: owners
  manage the allowlist from the canonical domain, so a bad list can always
  be fixed. Document this in the UI copy.
- **Client IP**: `env['otto.client_ip']` with
  `Otto::Utils.resolve_client_ip(env, env['otto.security_config'])`
  fallback — the canonical pattern from
  `admin_network_isolation.rb:120-128`. Never read XFF directly; never
  read `REMOTE_ADDR` (overwritten with the masked value).
- **Fail-closed on unresolvable IP** when a policy is enforcing (matches
  `AdminNetworkIsolation` and `LocalhostGuard` posture). Fail-open (no-op)
  when no config exists, config is disabled, or the entry list is empty.
- **Granularity: /24 (IPv4) and /48 (IPv6) minimum prefix.** A functional
  necessity given IP masking, not just privacy policy. Reuse
  `validate_cidr_privacy` (`lib/onetime/helpers/homepage_mode_helpers.rb:132-135`)
  verbatim at write time; reject narrower prefixes with an explanatory
  validation error ("entries must be /24 or wider").

### Default polarity — deliberate divergence from signin/signup

Sign-in/sign-up configs default **closed** for custom domains (ADR-024,
`resolve_signin_enabled_for_custom_domain`). The IP allowlist defaults
**open**: no config, master switch off, or empty entry list → no-op,
matching `AdminNetworkIsolation`'s empty-allowlist behavior
(`admin_network_isolation.rb:69`). An access-control feature that defaulted
closed would brick every existing custom domain on deploy.

### Enforcement middleware

New `Onetime::Middleware::DomainAccessControl`, mounted in
`lib/onetime/application/middleware_stack.rb` **immediately after
`DomainStrategy` (line 379)**. This is the only correct slot: it needs
`otto.client_ip` (set at line 296) and `onetime.domain_strategy`/
`onetime.display_domain` (set at line 379). The existing CIDR precedent
`AdminNetworkIsolation` (line 322) runs *before* host detection and cannot
be extended for this.

Flow per request:

1. Pass through unless `env['onetime.domain_strategy'] == :custom`.
2. Load the domain's `AccessConfig`; pass through unless present, enabled,
   and non-empty. (Dev note: the domain-context override forces `:custom`
   for any non-canonical host — the no-record path must pass through.)
3. Resolve client IP; if unresolvable → block (enforce) / log (monitor).
4. Match against compiled `IPAddr` entries (family-aware, `#native`-folded).
5. Miss + `mode: monitor` → structured `warn` log, pass through.
   Miss + `mode: enforce` → block response.

Blocked response: **403** with a branded human-readable explanation page for
HTML, JSON error body for `PATH_INFO` starting `/api` — same content
negotiation as `IPBan` (`lib/onetime/middleware/ip_ban.rb:44-46`). 404-style
hiding (the `AdminNetworkIsolation` choice) is rejected here: customers
configuring a corporate allowlist want employees on the wrong network to
understand why access failed (Atlassian model), and the domain's existence
is not a secret.

Performance: enforcement adds Redis reads only on custom-domain requests.
Free win while in there: `DomainStrategy#known_custom_domain?`
(`lib/onetime/middleware/domain_strategy.rb:281-286`) already loads the
`CustomDomain` record and discards it — stash it as
`env['onetime.custom_domain']` so the filter (and downstream controllers
that re-resolve) reuse it.

### Storage model

New sibling config model following the established per-domain template
(`lib/onetime/models/custom_domain/signin_config.rb:47-72`):

```
Onetime::CustomDomain::AccessConfig < Familia::Horreum
  prefix   :custom_domain__access_config
  identifier_field :domain_id
  field :domain_id
  field :enabled          # master switch, default false (init)
  field :mode             # 'monitor' | 'enforce', default 'monitor'
  field :allowed_cidrs    # JSON array: [{cidr:, label:, created:}, ...]
  field :created
  field :updated
```

- Cap: 100 entries per domain (GitHub/Okta territory; raise later if asked).
- Validation at write: parseable `IPAddr`, prefix ≥ /24 v4 / ≥ /48 v6,
  label ≤ 100 chars, de-dup by normalized CIDR. String keys throughout
  (Redis/REST boundary convention).
- Wire into the `CustomDomain` delegator/cleanup lists
  (`custom_domain.rb:334-362`, `:453`) and add a
  `models/domain-access-config` schema doc like its siblings.

### Management API

Uniform config quartet on the domains app, mirroring
`apps/api/domains/routes.txt:56-59`:

```
GET    /api/domains/:extid/access-config   auth=sessionauth
PUT    /api/domains/:extid/access-config   auth=sessionauth
DELETE /api/domains/:extid/access-config   auth=sessionauth
```

Logic classes under `apps/api/domains/logic/access_config/`, authorized via
`policies/domain_config_authorization.rb`, plan-gated with
`require_entitlement!` (`lib/onetime/logic/base.rb:214`) — proposed
entitlement key `ip_allowlist` (or fold into an existing security-tier
entitlement; billing decision).

**Entitlement gating applies to management only.** The enforcement
middleware runs on anonymous requests (secret links) where no `auth_org`
exists, so it reads only the stored config and never checks entitlements
per-request. Plan-downgrade handling: v1 accepts that an existing config
keeps enforcing after downgrade (management is locked, list is frozen);
if product wants downgrade-disables-enforcement, denormalize a flag at
plan-change time — do not check per-request.

**Self-lockout guard in `PUT`**: when `mode` transitions to `enforce`,
verify the requester's current resolved IP matches an entry; if not,
require an explicit `confirm_lockout: true` acknowledgment (Datadog
pattern, softened because canonical-domain management makes lockout
recoverable).

### Frontend

- Contract: `src/schemas/contracts/custom-domain/access-config.ts` + export
  from `index.ts`; CIDR-array shape precedent at
  `src/schemas/contracts/config/section/ui.ts:51`.
- Workspace: `DomainAccess.vue` view + route in
  `src/apps/workspace/routes/dashboard.ts` (pattern:
  `DomainSignin` at `:183-184`); `DomainAccessConfigForm.vue` under
  `src/apps/workspace/components/domains/` — entry table (CIDR, label,
  added), master toggle, monitor/enforce selector, current-IP indicator
  ("you are connecting from 203.0.113.0/24 — covered / not covered"),
  lockout warning, dual-stack IPv6 reminder.
- Colonel: read-only access-config block in
  `src/apps/admin/views/AdminDomainDetail.vue`.
- CLI parity: allowlist summary line in
  `apps/api/domains/cli/info_command.rb` (pattern at `:79`).

### Exemptions (scope contract, documented in UI + docs)

| Surface | Treatment |
|---|---|
| `/api/incoming` (anonymous inbound reports) | Exempt — external senders are never in a customer allowlist (`apps/api/incoming/routes.txt`) |
| ACME HTTP-01 challenges | Must remain reachable or cert renewal for the protected domain itself breaks. No in-app `/.well-known/acme-challenge` route found; TLS appears terminated upstream — **verify with ops**; exempt the path defensively if ever served in-app |
| Health endpoints | Already governed by `HealthAccessControl` (stack line 314); no change |
| Canonical-domain traffic | Out of scope by design (break-glass) |

### Audit and observability

- **Config changes** → org audit trail
  (`lib/onetime/models/organization/features/audit_trail.rb:60`,
  `record_audit_event`) — customer-visible, capped sorted set.
- **Blocked requests** → structured `warn` log always
  (`AdminNetworkIsolation` pattern, `admin_network_isolation.rb:80-86`)
  plus an aggregate counter. **Never** a per-request audit-trail write:
  that is a Redis write on an unauthenticated path — a write-amplification
  DoS vector. Sampled audit events at most.
- Monitor mode reuses the same log line with `mode: monitor` so customers
  can trial a list against real traffic before enforcing.

### Explicit non-goals (v1)

Deny lists, named reusable zones shared across domains, geo/ASN dynamic
rules (blocked upstream on Otto gap #4), step-up-instead-of-block,
login-only enforcement mode, Terraform provider.

---

## 5. Work breakdown

| # | Work | Anchors |
|---|---|---|
| 1 | `AccessConfig` model + validation + schema doc + delegators/cleanup | `signin_config.rb` template; `custom_domain.rb:334-362,453` |
| 2 | `DomainAccessControl` middleware + mount + env stash of resolved domain | `middleware_stack.rb:379`; `domain_strategy.rb:283`; `ip_ban.rb` response shape |
| 3 | API quartet + logic + authorization + entitlement key | `apps/api/domains/routes.txt:56-59`; `logic/signin_config/` template |
| 4 | TS contract + workspace view/form + route | `src/schemas/contracts/custom-domain/`; `dashboard.ts:183-184` |
| 5 | Colonel read-only block + CLI info line | `AdminDomainDetail.vue`; `cli/info_command.rb:79` |
| 6 | Audit events + blocked-request logging/counter | `audit_trail.rb:60` |
| 7 | Tests: middleware spec (strategy gating, monitor/enforce, fail-closed, exemptions, dev override), model tryouts (validation matrix incl. /25 rejection), logic specs, contract vitest | `spec/unit/onetime/application/middleware_stack_spec.rb` neighborhood |
| 8 | Docs: scope contract + lockout guidance; locales (`locales:hashes` run) | this file |
| 9 | Separate fix: `AdminNetworkIsolation` narrow-CIDR latent bug (validate or widen at boot, warn loudly) | `admin_network_isolation.rb:136-145` |
| 10 | Upstream Otto issues: `ip_in_cidrs?` primitive; pre-masking hook/unmasked key; geo-header proxy gate; ancestry-aware error dispatch | §3 |

Suggested sequencing: 1–2 (enforcement path, shippable dark), 3 (API), 4–5
(UI), 6–8 alongside; 9–10 independent.

## 6. Open questions

1. **Granularity**: is /24 (v4) / /48 (v6) minimum acceptable to product?
   Finer cleanly requires the Otto pre-masking hook (§3.3) first.
   Recommendation: ship at /24–/48; the masking constraint conveniently
   matches the existing privacy-preserving CIDR policy. Interim path if
   product rejects /24 before upstream lands: mount the filter *upstream*
   of `IPPrivacyMiddleware` (before `middleware_stack.rb:296`) and call
   the public `Otto::Utils.resolve_client_ip` on the raw env directly —
   ephemeral use, nothing stored, same idea as the hook implemented in
   our stack. Costs: duplicated IP resolution and moving host detection
   (`DetectHost`/`DomainStrategy`) ahead of the privacy middleware, a
   stack reshuffle with its own regression risk.
2. **ACME**: confirm with ops where HTTP-01 challenges are served for
   custom domains (upstream Caddy vs in-app) before enabling enforcement
   anywhere.
3. **Entitlement key**: new `ip_allowlist` vs existing security-tier
   entitlement; plan mapping in `apps/web/billing/metadata.rb`.
4. **Downgrade behavior**: freeze-but-enforce (v1 default) vs
   denormalized disable-on-downgrade.

## Implementation references

- Otto gem: `otto-2.6.0/lib/otto/utils.rb` (resolution),
  `lib/otto/security/config.rb` (trusted proxies),
  `lib/otto/security/middleware/ip_privacy_middleware.rb` (masking),
  `lib/otto/caddy_tls/localhost_guard.rb` (filter template)
- Stack order: `lib/onetime/application/middleware_stack.rb:246-411`
- Domain resolution: `lib/onetime/middleware/domain_strategy.rb`
- CIDR precedents: `lib/onetime/middleware/admin_network_isolation.rb`,
  `lib/onetime/helpers/homepage_mode_helpers.rb`
- Config-model template: `lib/onetime/models/custom_domain/signin_config.rb`
- Prior art decision: `0622-otto-homepage-matching-cidrs-CONSIDER.txt`
