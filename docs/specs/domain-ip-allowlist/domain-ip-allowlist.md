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
- **IP privacy middleware** (`IPPrivacyMiddleware`, auto-mounted innermost
  in 2.6.0; *since otto#219 it mounts outermost, so all other middleware
  sees masked values*): sets `env['otto.client_ip']` and
  `env['otto.via_trusted_proxy']` (*tri-state since otto#228: written only
  when proxy trust is configured*); masks IPs, scrubs UA/referer, rewrites
  forwarded headers.
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
   This was the binding granularity constraint for the feature — resolved
   2026-07-25 by the `otto.ip_match` capability (§3), which decouples
   matching precision from masking.
2. **No allow/deny-list primitive.** No `allow_ip`/`deny_ip`, no exposed
   CIDR-set matcher (`Config#trusted_proxy?` is the only one and it is
   single-purpose), no per-route IP policy interpretation. *Addressed:
   `Otto::Utils.ip_in_cidrs?` implemented 2026-07-25 (§3).*
3. **`filter` mode's XFF walk is leftmost-first and therefore spoofable**
   (`utils.rb:166-172`) unless the proxy tier *replaces* inbound XFF.
   Depth mode is the robust option but permanently disables
   `Request#secure?`'s forwarded-proto trust (modes are mutually
   exclusive, so `otto.via_trusted_proxy` is always false in depth mode).
   *Since fixed: otto#226 grants depth-mode peer trust
   (`via_trusted_proxy=true`, forwarded proto honored), otto#228 makes the
   key tri-state, and the depth `+1` remap off-by-one was dropped (#4028),
   so depth resolves the documented client and resists XFF padding.*
4. **Geo headers are trusted unconditionally** in the released 2.6.0
   (`otto-2.6.0/lib/otto/privacy/geo_resolver.rb:164-197`): `CF-IPCountry`
   et al. are honored with no trusted-proxy gate, and the built-in range
   table is a toy. Country-based blocking on this foundation would be
   client-spoofable. *Already fixed on otto main (unreleased): geo headers
   are now honored only when the request arrived via a configured CIDR
   trusted proxy (`geo_headers_trusted?`), and the guess table is removed.*
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

## 3. Otto changes (implemented 2026-07-25, pending release)

Per the prior repo decision (`0622-otto-homepage-matching-cidrs-CONSIDER.txt`):
policy stays in OTS; Otto grows small, reusable primitives.

Otto's privacy-by-default frame is right for a public open-source project,
but private/compliance deployments invert the priority: granular
auditability supersedes. The organizing principle is to separate two axes
the pre-change design conflated:

- **Observability posture** — what persists where anyone can see it (env
  keys, logs, fingerprints, error reports). A global invariant; the place
  for discrete, named modes.
- **Policy precision** — what an access-control *decision* may examine,
  ephemerally, at resolution time. A capability; the place for opt-in.

Before these changes the only route to /32 matching was
`disable_ip_privacy!` — changing the observability posture (unmasking
logs) to gain a filter. The changes below decouple the axes so precise
filtering composes with any posture. Implemented on the otto checkout
(`~/Projects/dev/delano/otto`, uncommitted on main; full suite 1749
examples green; changelog fragment
`changelog.d/20260725_ip_precision_and_privacy_profiles.rst`):

1. **`Otto::Utils.ip_in_cidrs?(ip, cidrs)`** (`lib/otto/utils.rb`) — the
   public CIDR-set matcher, sharing the trusted-proxy matcher's semantics:
   port stripping, `IPAddr#native` folding of IPv4-mapped IPv6,
   family-aware range skipping. Asymmetric strictness by design: runtime
   `ip` input fails closed (nil/blank/malformed → false), configuration
   `cidrs` entries fail fast (invalid → `IPAddr::InvalidAddressError`),
   because silently skipping an entry narrows an allowlist or widens a
   denylist. Accepts pre-parsed `IPAddr` entries for hot paths.
2. **Named privacy profiles** (observability axis) —
   `configure_ip_privacy(profile: :anonymous | :masked | :audit)`, also
   accepted by `Privacy::Config.new`. Validated presets over the existing
   knobs (`:masked` = default posture; `:anonymous` = mask everything;
   `:audit` = privacy disabled, operator owns retention). Explicit options
   in the same call override the preset; `Config#profile` is derived from
   live knob state so the label can never go stale; unknown names raise.
3. **`env['otto.ip_match']` verdict-only capability** (precision axis) —
   `IPPrivacyMiddleware` installs a closure over the resolved, *unmasked*
   client IP on every path that resolves one (masked, private-exempt, and
   `:audit`), before masking destroys the raw material. Downstream policy
   code calls it with a CIDR array and gets true/false at full /32–/128
   precision under any profile. Fails closed (returns false) when no
   client IP resolved; not installed when the idempotency guard trips
   (a prior instance already ran — and already installed it).

   This is a deliberate refinement of the earlier "boot-registered
   pre-masking hook" idea: a hook inside IPPrivacy cannot serve OTS's
   per-domain policy, because at that stack position (line 296) the
   domain is not yet resolved (line 379). The closure moves the *verdict*
   to where the policy context exists while keeping the contract: the
   unmasked IP never lands in env as data — a Proc serializes to nothing
   useful, so env dumps, loggers, and error reporters cannot leak it
   accidentally. (Deliberate in-process reconstruction via adaptive
   queries remains possible, but in-process code is already trusted; the
   invariant defended is accidental persistence.) The previously
   considered unmasked env key stays **rejected** — ambient authority
   that every env consumer silently joins.

Related, already on otto main before this change set (also unreleased):
trusted-proxy-gated geo headers (`geo_headers_trusted?` — prerequisite
for any future country rules) and removal of the `KNOWN_RANGES` guess
table. Not implemented, not needed for this feature: ancestry-aware
error-handler lookup (OTS middleware returns its own Rack tuple) and a
first-class `IPFilterMiddleware` (the capability + `ip_in_cidrs?` cover
it).

**Dependency**: this feature requires the next otto release; the OTS
Gemfile constraint `'~> 2.5'` already admits it.

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
- **Client IP matching**: exclusively via `env['otto.ip_match']` (§3.3) —
  the verdict-only closure over the resolved, unmasked client IP. Never
  read XFF directly; never match against `REMOTE_ADDR` or
  `env['otto.client_ip']` (both masked). Logging of blocked requests uses
  the masked `otto.client_ip` — the observability posture is unchanged.
- **Fail-closed** when a policy is enforcing and either the capability
  returns false with no resolvable IP, or `otto.ip_match` is absent
  entirely (stack misconfiguration — log loudly; matches
  `AdminNetworkIsolation` and `LocalhostGuard` posture). Fail-open (no-op)
  when no config exists, config is disabled, or the entry list is empty.
- **Granularity: full precision** — /32 (IPv4) and /128 (IPv6) entries are
  supported via the capability; the former /24–/48 floor (an artifact of
  matching against the masked IP) is lifted. The homepage-mode
  `validate_cidr_privacy` rule stays as-is for its own feature — it
  matches against the masked IP by design.

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
`otto.ip_match` (installed by `IPPrivacyMiddleware` at line 296) and
`onetime.domain_strategy`/`onetime.display_domain` (set at line 379).
The existing CIDR precedent
`AdminNetworkIsolation` (line 322) runs *before* host detection and cannot
be extended for this.

Flow per request:

1. Pass through unless `env['onetime.domain_strategy'] == :custom`.
2. Load the domain's `AccessConfig`; pass through unless present, enabled,
   and non-empty. (Dev note: the domain-context override forces `:custom`
   for any non-canonical host — the no-record path must pass through.)
3. `allowed = env['otto.ip_match']&.call(compiled_entries)` — pre-parsed
   `IPAddr` entries; the capability handles family awareness and
   `#native` folding. `false` covers both "outside every range" and "no
   resolvable client IP"; a missing capability is treated as a miss and
   logged as a stack error.
4. Miss + `mode: monitor` → structured `warn` log (masked IP), pass
   through.
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
- Validation at write: parseable `IPAddr` (any prefix incl. /32 and /128 —
  invalid entries would raise from `ip_in_cidrs?` at request time, so
  write-time validation is mandatory), label ≤ 100 chars, de-dup by
  normalized CIDR. String keys throughout (Redis/REST boundary
  convention).
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
rules (unblocked upstream now that geo headers are proxy-gated on otto
main, but still out of scope for v1), step-up-instead-of-block,
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
| 7 | Tests: middleware spec (strategy gating, monitor/enforce, fail-closed incl. missing `otto.ip_match`, exemptions, dev override, /32 precision), model tryouts (validation matrix), logic specs, contract vitest | `spec/unit/onetime/application/middleware_stack_spec.rb` neighborhood |
| 8 | Docs: scope contract + lockout guidance; locales (`locales:hashes` run) | this file |
| 9 | Separate fix: `AdminNetworkIsolation` narrow-CIDR latent bug — migrate its matching to `env['otto.ip_match']` once the otto release lands, which makes `/32` admin CIDRs work instead of merely rejecting them | `admin_network_isolation.rb:110-145` |
| 10 | ~~Upstream Otto~~ **done 2026-07-25** (`ip_in_cidrs?`, privacy profiles, `otto.ip_match`; geo gate pre-existing on main). Remaining: commit/release otto, then bump the gem here | §3; `~/Projects/dev/delano/otto` |

Suggested sequencing: 10 first (otto release is the dependency), then 1–2
(enforcement path, shippable dark), 3 (API), 4–5 (UI), 6–8 alongside;
9 after the gem bump.

## 6. Open questions

1. **ACME**: confirm with ops where HTTP-01 challenges are served for
   custom domains (upstream Caddy vs in-app) before enabling enforcement
   anywhere.
2. **Entitlement key**: new `ip_allowlist` vs existing security-tier
   entitlement; plan mapping in `apps/web/billing/metadata.rb`.
3. **Downgrade behavior**: freeze-but-enforce (v1 default) vs
   denormalized disable-on-downgrade.

Resolved: ~~granularity~~ — full /32–/128 precision via `otto.ip_match`
(§3, implemented 2026-07-25); no interim in-OTS workaround (rejected in
favor of the immediate Otto change).

## Implementation references

- Otto gem (released 2.6.0): `otto-2.6.0/lib/otto/utils.rb` (resolution),
  `lib/otto/security/config.rb` (trusted proxies),
  `lib/otto/security/middleware/ip_privacy_middleware.rb` (masking),
  `lib/otto/caddy_tls/localhost_guard.rb` (filter template)
- Otto dev checkout with the §3 changes: `~/Projects/dev/delano/otto` —
  `lib/otto/utils.rb` (`ip_in_cidrs?`), `lib/otto/privacy/config.rb`
  (`PROFILES`), `lib/otto/security/middleware/ip_privacy_middleware.rb`
  (`install_ip_match`), `lib/otto/env_keys.rb` (`IP_MATCH`),
  `spec/otto/ip_precision_capability_spec.rb`
- Stack order: `lib/onetime/application/middleware_stack.rb:246-411`
- Domain resolution: `lib/onetime/middleware/domain_strategy.rb`
- CIDR precedents: `lib/onetime/middleware/admin_network_isolation.rb`,
  `lib/onetime/helpers/homepage_mode_helpers.rb`
- Config-model template: `lib/onetime/models/custom_domain/signin_config.rb`
- Prior art decision: `0622-otto-homepage-matching-cidrs-CONSIDER.txt`
