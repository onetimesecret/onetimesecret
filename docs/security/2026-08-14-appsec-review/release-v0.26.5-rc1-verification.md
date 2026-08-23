# Release Verification — v0.26.5-rc1

**Date:** 2026-08-14 · **Trigger:** `release.published` webhook for
[`v0.26.5-rc1`](https://github.com/onetimesecret/onetimesecret/releases/tag/v0.26.5-rc1)
**Addendum to:** the 2026-08-14 application security review in this directory.

---

## 1. The release contains no code this review has not seen

```
$ git rev-list -n1 v0.26.5-rc1
21c3f6ac79973b3c951260601a61387bc55af809
$ git rev-parse origin/main
21c3f6ac79973b3c951260601a61387bc55af809
$ git diff --stat 21c3f6ac79973b3c951260601a61387bc55af809 v0.26.5-rc1
   (empty — identical trees)
```

`v0.26.5-rc1` is the **exact commit** the review was performed against. There is no delta to
audit, and one consequence that matters:

> **All three High findings — H-1, H-2, H-3 — ship in this release candidate.**

They are not regressions introduced by the release; they predate it. But an RC is the last
convenient point to fix them before the tag goes stable, and H-2 in particular is a one-line change.

| Finding | Ships in v0.26.5-rc1 | Fix effort |
|---|---|---|
| H-2 — non-owner member reaches the org's Stripe Customer Portal | Yes | one `require_owner: true` |
| H-1 — org member harvests colleagues' secret bearer tokens | Yes | redact non-owned identifiers + raise entitlement |
| H-3 — tenant SSO `allowed_domains` never called | Yes | call the method on both paths |
| M-7 — unauthenticated Redis exhaustion (no conceal rate limit) | Yes | add a limiter to the existing registry |
| M-14 — end-user session revocation does not revoke | Yes | delete the Redis blob |

---

## 2. Novelty check against the four prior in-repo audits

`docs/security/` already contains audits dated 2026-07-06, 2026-07-19, 2026-07-30, and 2026-08-06.
Cross-referenced to avoid re-filing known issues:

| Finding | Previously reported? |
|---|---|
| H-1 `receipt/recent?scope=org` bearer-token leak | **No** — no prior mention of `ListReceipts` or `scope=org` |
| H-2 billing portal ownership gap | **No** — no prior mention of `customer_portal` / `BillingPortal` |
| H-3 `SsoConfig#allowed_domains` dead code | **No** — no prior mention of `allowed_domains` / `valid_email_domain?` |
| M-14 active-session revocation | **No** — no prior mention of `check_active_session` / `remove_active_session` |
| M-7 unthrottled secret creation | **Related but distinct** — see below |

**On M-7.** The 2026-07-30 audit (finding #4) reported unthrottled **account creation**, describing
the impact as *"datastore growth (no TTL on the Customer hash) and unsolicited mail"*. That was
fixed — `create_account_rate_limiter.rb` exists and is registered. M-7 is the **same class of defect
on a higher-volume endpoint that was never given a limiter**: secret creation is the product's
primary write path, is reachable with no account at all, and lands in the datastore that also holds
sessions. The precedent is useful — it shows the team accepts and fixes this class — and it makes
the omission on `conceal` harder to justify as intentional.

---

## 3. The release's own security claims — all four verified

The release notes make four explicit security claims. Each was tested against a locally-booted
instance at this exact tag. **All four hold as written.**

### Claim 1 — `/colonel` host gate is active without config ✅

> *"admin surfaces now default to canonical `DEFAULT_DOMAIN`/`HOST` (+ `www.`)"*

With `HOST=secrets.example.com` and `ADMIN_ALLOWED_HOSTS` unset:

| Request `Host:` | `/colonel` | `/api/colonel/status` |
|---|---|---|
| `secrets.example.com` | 302 → `/signin` (gate allows; unauthenticated) | 404 |
| `www.secrets.example.com` | 302 → `/signin` (www variant allowed, as documented) | 404 |
| `evil.example.com` | **404** (gate denies) | 404 |
| `customer-domain.test` | **404** (gate denies) | 404 |

The stated intent — *"tenant custom domains and operator link-pool domains stop serving the admin
console"* — is exactly what happens.

**Operational caveat worth surfacing.** The gate **self-disables** when the canonical anchor is not
a routable hostname. With the default `HOST=localhost:3000` the boot log reads:

```
Admin host allowlist INACTIVE: no routable hostname configured
  source: "canonical anchors", hosts: ["localhost"]
  note: "localhost and bare-IP hosts are never detected as a host; set ADMIN_ALLOWED_HOSTS
         (or site.host / DEFAULT_DOMAIN) to a routable hostname to enable the host gate"
```

This is correct and deliberate — a bare-IP or `localhost` install would otherwise lock itself out —
and it is announced loudly rather than silently. But it means **the upgrade checklist's "gate is now
active" is conditional on a routable `site.host`**, and an operator serving on a bare IP gets no host
gate at all. Worth a line in the upgrade guide. (My first test run was inconclusive for precisely
this reason; re-running with a routable anchor produced the table above.)

### Claim 2 — `ADMIN_ALLOWED_CIDRS` with no valid entry now fails closed ✅

> *"previously degraded to 'no network restriction'"*

Booted with `ADMIN_ALLOWED_CIDRS='100.64.0.0\10,not-a-cidr,example.com'` (three unparseable entries):

```
WARN  Invalid CIDR in site.admin.allowed_cidrs, skipping: 100.64.0.010
WARN  Invalid CIDR in site.admin.allowed_cidrs, skipping: not-a-cidr
WARN  Invalid CIDR in site.admin.allowed_cidrs, skipping: example.com
ERROR Admin CIDR allowlist has no usable range; denying both admin surfaces
      note: "/colonel and /api/colonel are returning 404 to EVERY request ... Fix the entries
             (ADMIN_ALLOWED_CIDRS=100.64.0.0/10,10.0.0.0/8) or unset it entirely"
```

| Surface | Result |
|---|---|
| `/colonel` (both allowed hosts) | **404** — denied |
| `/api/colonel/status` | **404** — denied |
| `/api/v2/status` | 200 — unaffected |
| `/` | 200 — unaffected |

Fails closed, and the blast radius is correctly scoped to the two admin surfaces rather than taking
the app down. The code path is `resolve_network_gate` →
`unusable_network_gate` (`lib/onetime/middleware/admin_network_isolation.rb:675-689`), which returns
`[[], true]` — empty ranges, gate **active**. The sibling `unreadable_network_gate` (config read
raised) does the same, deliberately using a `CONFIG_UNREADABLE` sentinel rather than `nil` so
"unreadable" can never be mistaken for "unset". That distinction is the difference between failing
closed and failing open, and it is handled correctly.

### Claims 3 & 4 — `RABBITMQ_VERIFY_PEER` failing open; strict boolean parsing ✅

> *"It was read as `== 'true'`, so `1`, `yes`, or `TRUE` silently disabled TLS peer verification on a
> default-ON control."*

`Onetime::Utils::Strings.strict_bool!` (`lib/onetime/utils/strings.rb:299-311`) exercised directly:

```
TRUTHY: ["1", "true", "yes", "on", "y", "t"]
FALSEY: ["0", "false", "no", "off", "n", "f"]

the tokens that used to fail open:   "1" "yes" "TRUE" "on" "y" "t"  -> all true  ✅
explicit disables:                   "false" "no" "off" "0" "n" "f" -> all false ✅
typos ("yess","tru","enabled","2"):  raise Onetime::ConfigError               ✅
unset / "" / "   ":                  fall back to the default (true)          ✅
```

The fix is real: values that previously disabled TLS peer verification now enable it, and a typo
fails the boot instead of silently disabling a default-ON control.

**Worth calling out as good practice:** the error message does not echo the offending value — it
reports the character count and a truncated SHA-256, because these env vars sometimes hold secrets:

```
RABBITMQ_VERIFY_PEER is set to an unrecognized boolean
(4 chars, sha256:a7d7c16d). Use one of 1/true/yes/on/y/t or 0/false/no/off/n/f, or leave unset.
```

---

## 4. Effect of the TTL clamp removal (#4022) on M-7

The release removes a hardcoded 30-day TTL clamp. Checked against M-7's measurements:

- **Anonymous ceiling is unchanged at 7 days** — `site.secret_options.ttl_max_anonymous` defaults to
  `7.days` (`lib/onetime/config.rb:67`), and a live probe requesting `ttl=99999999999` still clamps
  to `604800`. M-7's reproduction (~16 KB of 7-day-persistent Redis per unauthenticated request)
  therefore **stands exactly as measured**.
- The global ceiling is now `30.days` (`config.rb:61`) for plan-entitled callers. That raises the
  authenticated per-secret retention 4×, which amplifies the *authenticated* abuse case of the same
  missing limiter — but M-7 is filed on the unauthenticated path, and that number did not move.

No change to the finding's severity or reproduction.

---

## 5. Bottom line for this release

Nothing in v0.26.5-rc1 introduces a new vulnerability, and the security work the release advertises
is real — the three fail-closed gates and the boolean-parsing fix all do what the notes say, and the
`admin_network_isolation` code is careful in ways that are easy to get wrong (the unreadable-vs-unset
sentinel especially).

The open question is not about the release's changes; it is that the RC ships three unfixed High
authorization findings. H-2 is a one-line fix and would be a cheap thing to land before the tag goes
stable.

One documentation gap to consider for the upgrade guide: the `/colonel` host gate is conditional on a
routable `site.host`, and installs serving on `localhost` or a bare IP get no host gate at all.
