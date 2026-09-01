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
