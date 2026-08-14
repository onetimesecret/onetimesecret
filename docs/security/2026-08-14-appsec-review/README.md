# Application Security Review — OneTimeSecret

**Date:** 2026-08-14
**Reviewer:** Application Security Engineer (automated deep review)
**Method:** Full source review of 6 repositories + live black-box and grey-box testing against a
locally-booted instance with synthetic data only.

---

## 1. Repositories reviewed

All six repositories were read. **Only `onetimesecret` is the deployed application** — the other
five are developer working copies of gems that the build resolves from rubygems.org, *not* from
these paths. This was verified: `Gemfile` has no `path:`/`git:` options, `Gemfile.lock` contains
only a `GEM` section, and there is no `.bundle/config` override.

| Repository | Branch (checked out) | Commit | Head commit date | Version in use |
|---|---|---|---|---|
| `onetimesecret/onetimesecret` | `agent/fervent-pascal-0y5cji` | `21c3f6ac79973b3c951260601a61387bc55af809` | 2026-08-13 | `0.0.0-rc0` |
| `delano/otto` | `agent/busy-mendel-0y5cji` | `e867fcde249a78e1a7a383356049fc4000a277c1` | 2026-08-07 | gem `otto 2.8.0` |
| `onetimesecret/rhales` | `agent/optimistic-darwin-0y5cji` | `ca79eaf251436ef9dcab4581113fcd4d8fd39fda` | 2026-06-22 | gem `rhales 0.7.1` |
| `delano/familia` | `agent/fervent-planck-0y5cji` | `c7eb1a1f27c6b59115aaac392dec9456d89e7bc4` | 2026-08-05 | gem `familia 2.12.0` |
| `onetimesecret/rodauth` | `agent/relaxed-rubin-0y5cji` | `82ede25ddab025e5d83f76da104e76fb8968952d` | 2026-08-10 | gem `rodauth 2.45.0` |
| `onetimesecret/rodauth-omniauth` | `agent/quirky-allen-0y5cji` | `9fe8152732f7f5409e392239411bd47fc6bf6e0a` | 2025-08-03 | gem `rodauth-omniauth 0.6.2` |

**Fork drift check.** `onetimesecret/rodauth` differs from the installed `rodauth 2.45.0` in exactly
two files (`change_password.rb`, `verify_account.rb`); both are upstream-master hardening commits.
`onetimesecret/rodauth-omniauth` has a clean tree at tag `0.6.2` — no divergence from upstream.
Neither fork weakens token generation or comparison. Since neither is wired into the build, fork
drift is currently a non-issue.

---

## 2. Documents in this review

| File | Contents |
|---|---|
| `README.md` | This document — scope, method, repo provenance |
| `findings.md` | Full findings report: severity, evidence, reproduction, impact, remediation |
| `risk-register.md` | Prioritized register with exploitability × business-impact ratings |
| `tooling.md` | Every tool installed, every command run, and how to reset the environment |
| `poc/` | Runnable proof-of-concept scripts for the reproducible findings |

---

## 3. Headline result

The application is **well engineered for security**. The core product invariant — burn-after-reading
— holds under concurrency; CSP is strict and nonce-based; there is no committed secret and no
default secret that silently works in production; CORS is absent by design; mass assignment does
not occur anywhere; and `X-Forwarded-For` is not trusted by default.

The findings that matter are concentrated in three places:

1. **Intra-tenant authorization on the receipts listing** — the lowest-privilege org role can
   harvest colleagues' secret bearer tokens (H-1).
2. **Billing authorization** — a non-owner member can reach the organization's Stripe Customer
   Portal (H-2).
3. **A tenant SSO access control that does not exist at runtime** — `SsoConfig#allowed_domains`
   is configured, surfaced in the UI, documented as the access control for generic OIDC, and
   never called (H-3).

Four claims that a first-pass review flags as Critical were **empirically refuted** during live
testing and are documented in `findings.md` §5 so they are not re-raised.

---

## 4. Coverage against the requested focus areas

| # | Focus area | Coverage | Result |
|---|---|---|---|
| 1 | Authentication & session management | Full source + live | M-1…M-4, plus 4 refuted claims |
| 2 | Authorization / IDOR / tenant isolation | Full source | H-1, H-2, M-5, M-6, L-1, L-2 |
| 3 | Redis-specific risks | Full source + live | M-7 (DoS, reproduced); deserialization/Lua/SCAN clean |
| 4 | REST API security | Full source + live | M-7, L-3; CORS/mass-assignment/error-handling clean |
| 5 | SPA security | Full source + live | M-8, M-9, M-10, L-4 |
| 6 | Supply chain | Full source + `bundler-audit` | M-11, M-12, M-13, L-5, L-6 |
| 7 | Runtime & deployment | Full source | L-7; secrets/containers/compose clean |
| 8 | Business logic | Full source + live | H-1, M-2, M-3, M-4, L-8 |
| 9 | Cryptography | Full source + live | Clean; see §6 of `findings.md` |
| 10 | Observability | Full source | M-14, L-9 |

---

## 5. Constraints honoured

- No fixes deployed to any shared branch or environment. This branch contains **documentation
  only** — no application code was changed in the commit.
- No production-facing configuration modified.
- No traffic sent to any external endpoint. All testing was against `127.0.0.1:3000` with a
  local Redis on `127.0.0.1:6379`.
- Synthetic data only. No production database or credential was accessed.
- Every local environment change is documented in `tooling.md` §4 with its reset command.
