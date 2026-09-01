# Colonel admin console — self-hosted operator guide

The **Colonel** admin console is the operating console for a Onetime Secret
install: a support and operations surface that replaces one-off SSH/CLI work with
a single audited UI. This guide is for operators of self-hosted deployments.

It covers:

1. [Promoting a colonel](#1-promoting-a-colonel-cli-only) (CLI only).
2. [What the console can do](#2-what-the-console-can-do).
3. [Restricting the admin surfaces](#3-restricting-the-admin-surfaces) by
   hostname and by network.

The console lives at **`/colonel`** and is served to any signed-in account that
holds the `colonel` role. Since the cutover it is the sole admin frontend (the
legacy colonel SPA has been retired); `/colonel` serves the rebuilt console
unconditionally.

## 1. Promoting a colonel (CLI only)

Colonel is a privileged role and is granted **only** from the command line, on
the host. The console never grants roles to itself — there is no "make me an
admin" button, by design, so a compromised session cannot escalate.

Promote an existing, **verified** account:

```bash
bin/ots customers role promote user@example.com
```

Other role commands:

```bash
bin/ots customers role promote user@example.com --role admin   # promote to a specific role
bin/ots customers role demote  user@example.com                # back to customer
bin/ots customers role list                                    # list all colonels
bin/ots customers role list --role admin                       # list a specific role
```

Notes:

- The account must **exist** and be **verified** first — a system role requires
  `cust.verified?`. Create/verify the account through normal sign-up before
  promoting.
- The mutation runs through the shared `Auth::Operations::Customers::SetRole`
  operation (the same implementation the admin API uses), so it records an
  `ColonelAuditEvent` (actor / verb / target / result) just like a UI action.
- Add `-f`/`--force` to skip the confirmation prompt in automation.
- To revoke access, `demote` the account; the role is removed immediately.

### Self-target and last-colonel interlocks (#4328)

The console refuses four things outright, with a 422 naming the remediation:

| Action | Why it is refused |
|---|---|
| Demoting **your own** colonel account | Nobody else could undo it from the console. |
| Demoting the **last remaining** colonel | The install would have no administrator. |
| **Unverifying** your own account | A system role requires `cust.verified?`, so unverifying is a demotion by another name. |
| Unverifying the **last remaining** colonel | Same, applied to the whole install. |

The last two matter more than they look: unverifying used to be an un-gated
POST that stripped colonel eligibility straight past any last-colonel check on
the role endpoint.

**The CLI is the recovery path, and it is interlocked too.** `bin/ots customers
role demote` and `bin/ots customers unverify` refuse the last remaining verified
colonel and exit non-zero — the refusal lives in the shared operation, not in
the HTTP adapter, so there is no way around it short of editing Redis. To
actually hand over the last colonel account, promote **and verify** the
replacement first, then demote.

"Last remaining colonel" is computed from the authoritative `role` field on
every candidate, not from `customer:role_index:colonel`. That index drifts
UPWARD (see `bin/ots customers role reconcile`), so counting it would make the
guard fail open and let you demote the only administrator you have.

Two session verbs carry the same self-target rule:

- Revoking **your own** session, from either the global console or the
  per-customer panel, is refused — sign out instead.
- Revoking **all** sessions on your own account is **not** refused. It is the
  first containment step for a leaked colonel cookie, so it runs the
  except-current variant: every other session dies and the one you are working
  in survives.

## 2. What the console can do

Every capability is enforced by the two-layer authorization invariant (router
`role=colonel scope=internal` **plus** `verify_one_of_roles!(colonel: true)` in
the logic), and every mutating action is written to the audit log. Destructive
verbs are guarded by typed-confirmation dialogs.

| Section | Path | What it does |
| ------- | ---- | ------------ |
| Overview | `/colonel` | Console map + at-a-glance stats. |
| Customers | `/colonel/customers` | Filterable customer list + detail; verify/unverify, plan, role, purge — support without SSH. |
| Secrets | `/colonel/secrets` | List + receipt inspection + guarded delete. |
| Organizations | `/colonel/organizations` | Org list, billing-investigate, entitlement overrides. |
| Domains | `/colonel/domains` | Custom-domain grid + per-domain verify. |
| System | `/colonel/system` | Database / Redis / queue metrics read-out. |
| Usage | `/colonel/usage` | Usage-export read-out. |
| Sessions | `/colonel/sessions` | Inspect / search / revoke sessions. |
| Banner | `/colonel/banner` | Set / show / clear the broadcast banner. |
| Queue DLQ | `/colonel/queues/dlq` | Inspect dead-letter queues; guarded replay / purge. |
| Domain toolbox | `/colonel/domain-toolbox` | Orphaned-scan, probe; guarded repair / transfer. |
| Email + rate-limit | `/colonel/email-tools` | Template preview, test send, limiter inspect / reset. |
| Billing catalog | `/colonel/billing` | Read-only plan-drift view. |

The JSON API behind the console is `/api/colonel/*` (scope `internal`, not part
of the public API contract). Its full route inventory and the authorization
assertions each route must satisfy are in `docs/operations/pentest-scope.md`.

### Audit trail

Every mutating operation records exactly one `ColonelAuditEvent` capturing the
acting colonel, the verb, the target, and the result — whether it originated
from the console or the CLI (both go through the same shared operations). This is
the non-negotiable backstop for privileged actions.

### Destructive-action confirmation — `X-OTS-Confirm`

Typed-confirmation used to live only in the browser: past the console, purge,
delete, revoke and DLQ-purge executed on a bare authenticated request. They are
now checked **server-side**. A gated verb is refused with **403
`error_code: confirmation_required`** unless the request carries an identifier of
the target in the `X-OTS-Confirm` request header.

- **A header, not a query or body parameter.** Most of these tokens are an email
  address, an organization name or a hostname — PII that a query string writes
  into every access log, proxy log and browser history. `?confirm=…` is ignored;
  it is not a fallback.
- **Percent-encoded**, because HTTP header values are ISO-8859-1 by RFC 7230 and
  an organization display name may not be. A plain ASCII token is unchanged by
  encoding, so `curl -H 'X-OTS-Confirm: victim@example.com'` works as typed.
- **Apply only.** A verb with a `dry_run` preview needs no header to preview; the
  preview writes nothing. `dry_run` defaults to TRUE on the domain and
  organization verbs and FALSE on the DLQ verbs.
- **The console sends it for you.** This matters to scripted callers and to the
  eleven endpoints below that have no UI at all.

Eighteen of the twenty-five gated verbs ask for an identifier the URL does not
carry, so a scraped-URL replay needs a second fact about the target. The two DLQ
verbs echo the queue name because a queue has no second identifier.

| Endpoint | `X-OTS-Confirm` must equal | UI? |
| -------- | -------------------------- | --- |
| `DELETE /secrets/:secret_id` | the receipt **shortid** | yes |
| `POST /users/:user_id/email` | the account's **current email** | no |
| `POST /users/:user_id/role` | the account **email** (its extid when it has none) | yes |
| `POST /users/:user_id/unverify` | the account **email** | yes |
| `POST /users/:user_id/suspend` | the account **email** | yes |
| `DELETE /users/:user_id` | the account **email** | yes |
| `POST /users/:user_id/sessions/revoke-all` | the account **email** | yes |
| `DELETE /users/:user_id/sessions/:session_handle` | the session owner's **email** | yes |
| `DELETE /sessions/:session_handle` | the session owner's **email** (its external id, or the handle for an anonymous session) | yes |
| `POST /domains/:extid/repair` | the **domain name** | yes |
| `POST /domains/:extid/override` | the **domain name** | yes |
| `POST /domains/:extid/transfer` | the **domain name** | yes |
| `DELETE /domains/:extid` | the **domain name** | yes |
| `PUT\|DELETE /domains/:extid/configs/:kind` | `"<domain name>:<kind>"` | yes |
| `POST /organizations/:org_id/transfer-ownership` | the organization **name** (its extid when it has none) | no |
| `POST /organizations/:org_id/members` | the organization **name** | yes |
| `POST\|DELETE /organizations/:org_id/entitlements/…` | the organization **name** | yes |
| `DELETE /organizations/:org_id` | the organization **name** | yes |
| `POST /organizations/:org_id/members/:member_id/role` | the member's **email** | no |
| `DELETE /organizations/:org_id/members/:member_id` | the member's **email** | no |
| `POST\|DELETE /organizations/:org_id/members/:member_id/entitlements/…` | the member's **email** | no |
| `POST /queues/dlq/:queue/purge` | the **queue name** | no |
| `POST /queues/dlq/:queue/replay` | the **queue name** | no |
| `POST /ratelimit/reset` | `"<kind>:<subject>"` | no |

A refusal writes **no audit event** — deliberately. `ConfirmationRequired` is in
the `Forbidden` family, which the auto-audit path excludes, so hammering the gate
cannot mint events and flush the count-capped operator trail.

Which verbs are gated, and which mutating verbs are deliberately **not**, is
committed data in `apps/api/colonel/destructive_actions.rb`; a spec fails if a
new mutating route appears in none of the three lists.

### Step-up (sudo) re-authentication — `POST /api/colonel/elevation`

On top of confirmation, the **tier-1** verbs (the fifteen irreversible,
credential-revoking or privilege-granting ones — purge, role change, session
revoke, secret/org/domain/config delete, domain transfer, DLQ purge) also require
a live **elevation window**. A colonel session alone is no longer sufficient for
any of them: the operator must have re-proven a credential in the last ten
minutes. A verb attempted outside a window is refused with **403
`error_code: elevation_required`**, carrying the window length in seconds.

```
GET    /api/colonel/elevation   → { record: { elevated, expires_at, seconds_remaining },
                                    details: { enabled, window, reauth_grace,
                                               grace_available, password_available, factors } }
POST   /api/colonel/elevation   → { "factor": "password", "password": "…" }
DELETE /api/colonel/elevation   → ends the window early
```

- **The console does this for you.** A 403 opens an in-place sudo prompt, and the
  refused call is retried **once, after** the operator completes it. It is never
  retried silently.
- **The window is per session AND per identity.** A second browser elevates
  separately, and signing in as a different account in the same browser lands
  unelevated — the stored value names the account that minted it, and both login
  paths delete it outright.
- **Two factors.** `password` re-verifies the account password and is the only
  factor available by default. `recent_auth` elevates with no credential inside a
  post-sign-in grace, but ONLY for accounts that cannot satisfy the password
  factor and ONLY when an operator sets a non-zero
  `COLONEL_ELEVATION_REAUTH_GRACE` (**default 0 — off**). Giving that grace to
  password holders would make step-up a no-op for the first N seconds after every
  colonel sign-in, which is the exact condition this control exists to remove.
  MFA as a step-up factor is not implemented.
- **SSO-only fleets must configure one of two things.** A colonel with no password
  cannot elevate at all otherwise. Either set
  `COLONEL_ELEVATION_REAUTH_GRACE` to a non-zero number of seconds, or set
  `COLONEL_ELEVATION_ENABLED=false` (confirmation still applies). In **full auth
  mode** the password probe is not reachable from the API layer, so every account
  there counts as password-holding and `recent_auth` is unavailable —
  a full-mode SSO-only fleet uses `COLONEL_ELEVATION_ENABLED=false`.
  `GET /api/colonel/elevation` reports `password_available` and `factors` for the
  calling account, so the console can say which of these applies.
- **The console does not poll this endpoint**, and must not be made to. Every
  authenticated request advances the session's `last_activity_at`, so a polling
  banner would keep an idle admin tab alive forever and disable the admin idle
  timeout. The countdown you see is computed in the browser from `expires_at`.

**Throttle.** `POST /api/colonel/elevation` is limited to 5 attempts per 15
minutes per colonel account, then a 15-minute lockout — the password check behind
it is a Rodauth *internal request*, which does not increment Rodauth's own lockout
counter, so this limiter is the only backstop against guessing. Clear a stuck
lockout with `POST /api/colonel/ratelimit/reset` (kind `colonel_elevation`,
subject the colonel's extid — a tier-2 verb, so it needs no elevation), or with
the commands `bin/ots ratelimit keys colonel_elevation <extid>` prints.

**Audit.** A successful step-up records `colonel.elevate` on the operator trail
*carrying the factor used*, so a password-less `recent_auth` window is visible as
the weaker path. A failed attempt records the same `colonel.elevate` verb with
`result: failure` into the **security** collection (`record_security`: 7-day
retention, its own cap), never the operator trail, because a cookie holder can
drive failures on demand. Reaching the throttle records `colonel.elevate_throttled`
there too, once per lockout window. Dropping a window records
`colonel.elevate_drop`. An `ElevationRequired` refusal records **nothing at all**,
for the same reason as the confirmation gate.

**Residual risk, stated rather than hidden.** Elevation is carried by the session.
While a window is live, a stolen session cookie is exactly as capable as it was
before this feature existed. What the window buys is that the capability is
time-bounded, operator-initiated and audited instead of standing. Binding it to a
value the cookie does not carry — an elevation nonce echoed as a request header —
is the follow-up, and is not implemented here. Do not read (or write) release
notes implying that cookie theft is now bounded by the credential.

Configuration lives under `site.admin.elevation` and `site.admin.rate_limit` in
`etc/defaults/config.defaults.yaml`; every knob has an env var, listed in
`.env.reference`.

### Rate limits on `/api/colonel/*` (#4329)

Before this, nothing throttled the colonel API at all: a scripted compromise of a
colonel session could purge at wire speed and, because the operator audit trail
trims at a 10 000-event count cap with no TTL, evict the evidence of its own
actions while doing it. Four buckets now bound it. All four are keyed on the
**acting colonel's `extid`** — the same public id the audit trail records as
`actor`, never a session id (that value *is* the bearer cookie) — so a second
stolen session or a parallel tab shares one budget rather than getting a fresh
one.

| Kind | Limit | What it covers |
|---|---|---|
| `colonel_mutation` | 120 / 5 min, 5 min lockout | every mutating colonel verb (POST/PUT/PATCH/DELETE), charged once per request |
| `colonel_destructive` | 10 / 5 min, **15 min** lockout | the fifteen tier-1 verbs, charged **only when the request is about to execute** |
| `colonel_handle_resolve` | 60 / 5 min, 5 min lockout | `GET`/`DELETE /sessions/:session_handle`, the two reads that may fall back to a bounded 10 000-key scan |
| `colonel_elevation` | 5 / 15 min, 15 min lockout | `POST /elevation` (above) |

Over a cap the API answers **429** with the usual body — `error`, `error_type:
"LimitExceeded"`, `retry_after`, `max_attempts` — plus a `Retry-After` header.
The console renders the server's message in the confirm dialog and appends the
wait and the recovery path.

Three things worth knowing:

- **Ordinary reads are deliberately unlimited.** The console fetches several on
  every screen; throttling them would break the dashboard. The two
  handle-resolving session reads are the one exception, because each can cost a
  bounded scan plus as many HMACs.
- **A refused destructive attempt costs nothing.** The destructive charge is the
  last step of the guard sequence — after step-up, confirmation and the per-verb
  interlocks all pass — so the ten are ten *real* actions, not five plus five
  wasted pre-elevation retries, and nobody holding your cookie can lock you out
  of incident response with cheap 403s. Volume is still bounded meanwhile by the
  broad `colonel_mutation` bucket.
- **A destructive burst is a bulk-work signal.** Ten actions per five minutes is
  sized for incident response, not for migrations. Bulk work belongs on
  `bin/ots`, which these limiters do not touch.

**Clearing a lockout.** `POST /api/colonel/ratelimit/reset` with `kind` set to the
bucket and `subject` set to the colonel's extid; it is a tier-2 verb, so it needs
no elevation and stays reachable while the destructive, handle-resolve or
elevation bucket is exhausted. The one bucket it cannot rescue you from is
`colonel_mutation` — the reset is itself a mutation — so clear that one with the
valkey-cli commands `bin/ots ratelimit keys colonel_mutation <extid>` prints
(the CLI only prints them; it never connects). `bin/ots ratelimit inspect
<kind> <extid>` shows the current counter and lockout TTL.

**Audit.** Only the **cap-reaching** request writes an event, into the security
collection (`record_security`: 7-day retention, its own cap), never the operator
trail: `colonel.mutation_throttled`, `colonel.destructive_throttled`,
`colonel.handle_resolve_throttled`, `colonel.elevate_throttled`. Every subsequent
429 inside the lockout window writes nothing, which is what keeps a throttled
attacker from minting events.

**If Redis is unavailable** the limiters fail **closed**: a colonel mutation 500s
rather than being admitted unthrottled. That matches every other limiter in the
codebase.

### Admin session lifetime (#4331)

`/api/colonel*` expires on its own schedule, independently of the session cookie.

| Bound | Default | Source | Env var |
| --- | --- | --- | --- |
| Idle | 1 h | `SessionMetadata#last_activity_at` (the per-session sidecar) | `ADMIN_SESSION_IDLE_TIMEOUT` |
| Absolute | 12 h | `session['authenticated_at']`, stamped at sign-in | `ADMIN_SESSION_ABSOLUTE_TIMEOUT` |

Exceeding either answers **401** with
`[ADMIN_SESSION_EXPIRED] Admin session <idle|absolute> timeout exceeded; sign in
again`. Set either to `0` to disable that bound, or
`ADMIN_SESSION_LIFETIME_ENABLED=false` to restore the pre-#4331 posture.

**What this does NOT do, on purpose.** It does not shorten the `onetime.session`
cookie: one cookie serves the admin console, the tenant app and the auth app, so
expiring the object would log a colonel out of the customer app — and on a
self-hosted install the colonel is frequently the only customer.
`site.session.expire_after` (24 h rolling) still governs the session itself. It
also does not gate the `/colonel` SPA shell: the shell loads on a stale session,
its first API call 401s, and the console renders an expired banner with a
sign-in link rather than a bare JSON error on an HTML navigation.

**Recovery is sign-in.** There is no refresh endpoint — signing in replaces the
session, which also drops any step-up window. Nothing else in the console
changes.

**Two caveats worth understanding before you rely on the idle bound.** The
sidecar it reads is best-effort: a session that predates the feature or whose
30-day sidecar TTL lapsed has no record, and a missing record SKIPS the idle
check rather than failing it (the absolute bound still applies). And that record
is a **site-wide** activity clock, so a colonel who is browsing the tenant app
keeps their admin window open too. A request the bound refuses does not stamp
activity — an expired window stays expired across retries — but per-surface idle
tracking needs the separate admin session that splitting the cookie would give.

**If you build anything against the console:** the idle bound only bites because
the admin SPA makes no periodic requests. Any polling added under
`src/apps/admin/` would refresh `last_activity_at` forever and silently disable
this control.

## 3. Restricting the admin surfaces

Two independent factors restrict which requests reach `/colonel*` and
`/api/colonel*`, as **defense-in-depth** on top of the two auth layers above.
A request failing either one receives a **404** (indistinguishable-from-absent),
not a 403.

**Host — `site.admin.allowed_hosts` / `ADMIN_ALLOWED_HOSTS`, active by
default.** Which hostnames serve the admin surfaces. Unset, it falls back to the
canonical anchor hosts (`DEFAULT_DOMAIN` / `HOST`) plus their `www.` siblings, so
tenant custom domains and link-pool domains stop serving the console. Set it to
a dedicated hostname (`admin.example.com`) if you have one. On an install where
it is **unset** and there is no routable hostname to anchor on — the stock
`HOST=localhost:3000`, or access by bare IP — the gate self-disables with a boot
warning, so single-container installs are unaffected. A value that is set but
can never match (an IP address, `*.example.com`, a non-ASCII name) **404s both
admin surfaces** instead, with a boot warning naming what it rejected; the boot
itself is not aborted, since the surfaces are already fail-closed and the rest
of the app is unaffected. `ADMIN_ALLOWED_HOSTS=*` — anywhere in the list — is
the one way to turn the gate off, and the one-variable rollback.

Behind a proxy that forwards the public hostname in a header (`X-Forwarded-Host`,
`Apx-Incoming-Host`, …) rather than rewriting `Host`, `site.network.trusted_proxy`
must be configured **with the proxy's own address ranges in `cidrs`**: the host
gate accepts a forwarded host only from a peer that trust vouched for, so
otherwise both surfaces 404 — and filter mode with no explicit CIDRs trusts
every private-network peer as a proxy, which restores exactly the
forwarded-host spoofing the provenance rule exists to block.

**Network — `site.admin.allowed_cidrs` / `ADMIN_ALLOWED_CIDRS`, opt-in.** Which
client IPs may reach the surfaces. Unset (the default) it is a no-op, the right
posture for a self-hosted single-container install that cannot require a VPN. Do
not put public CIDRs in the allowlist — the app-layer auth remains the gate for
anyone already on the trusted network.

Both are a config posture, not a code fork — the same app-layer enforcement runs
underneath regardless. The full setup (upgrade impact, private CIDRs, the
required `site.network.trusted_proxy` with explicit proxy CIDRs behind a load
balancer, and the edge alternative) is documented in
**`docs/operations/admin-network-isolation.md`**.
