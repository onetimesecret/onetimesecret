# Colonel admin console — self-hosted operator guide

The **Colonel** admin console is the operating console for a Onetime Secret
install: a support and operations surface that replaces one-off SSH/CLI work with
a single audited UI. This guide is for operators of self-hosted deployments.

It covers:

1. [Promoting a colonel](#1-promoting-a-colonel-cli-only) (CLI only).
2. [What the console can do](#2-what-the-console-can-do).
3. [Enabling CIDR network isolation](#3-enabling-cidr-network-isolation).

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
  `AdminAuditEvent` (actor / verb / target / result) just like a UI action.
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
| Banned IPs | `/colonel/banned-ips` | List + guarded ban / unban. |
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

Every mutating operation records exactly one `AdminAuditEvent` capturing the
acting colonel, the verb, the target, and the result — whether it originated
from the console or the CLI (both go through the same shared operations). This is
the non-negotiable backstop for privileged actions.

## 3. Enabling CIDR network isolation

By default the two auth layers above are the sole gate, which is the right
posture for a self-hosted single-container install (no VPN required — no extra
configuration needed).

As **defense-in-depth**, you can additionally restrict both admin surfaces
(`/colonel*` and `/api/colonel*`) to a trusted network with
`site.admin.allowed_cidrs`. When set, a request from outside the allowlist
receives a **404** (indistinguishable-from-absent), not a 403.

This is a config posture, not a code fork — the same app-layer enforcement runs
underneath regardless. The full setup (private CIDRs, the required
`site.network.trusted_proxy` behind a load balancer, and a reverse-proxy
alternative) is documented in **`docs/operations/admin-network-isolation.md`**.
Do not put public CIDRs in the allowlist — the app-layer auth remains the gate
for anyone already on the trusted network.
