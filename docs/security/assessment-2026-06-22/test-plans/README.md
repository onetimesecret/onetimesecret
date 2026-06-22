# Test-case prescriptions — security remediation (assessment 2026-06-22)

QA prescription documents for the OneTimeSecret security-remediation effort. Each file enumerates the
test cases that MUST exist when the corresponding fix is implemented, so coverage is guaranteed up front.
These are **prescriptions, not implementations** — they are written against the *prescribed* APIs in the
resolution docs and intentionally land before (or alongside) the application code.

Branch: `claude/vigilant-goldberg-97ijfl`. Source under test is READ-ONLY for QA; only this directory is
authored.

## Index

| Plan | Resolutions covered | Cases | Headline gate |
|---|---|---|---|
| [`C1.md`](./C1.md) | C1 — atomic one-time consume (reveal/burn) | 23 | Multi-process race: N reveals → exactly 1 plaintext |
| [`S1-S2.md`](./S1-S2.md) | S1 — CSP default-on; S2 — security headers default-on | 21 | Default boot is secure-by-default; SPA enforces CSP with zero violations |
| [`SSO-3499-A1-A4-A2.md`](./SSO-3499-A1-A4-A2.md) | #3499, A1 — secure linking, A4 — domain allowlist on linking, A2 — MFA not bypassed | 30 | SSO email-match takeover blocked; SSO no longer bypasses enrolled MFA |

Total prescribed test cases: **74** (C1: 23, S1/S2: 21, SSO: 30).

## How each case is specified

For every test case: **ID · title · layer · target file/spec path · preconditions/fixtures · action ·
expected result · case type** (regression / negative / concurrency / edge). Each plan ends with a
**coverage matrix** (resolution acceptance criteria → test IDs) and a **Gaps / Risks** section.

### Layers / where tests live
- **unit** — RSpec model/operation specs and `try/` tryouts (`#=>` doctest format). No HTTP.
- **integration** — RSpec exercising logic classes / Rodauth callbacks end to end against real
  Valkey + AUTH DB (`apps/api/v{1,2}/spec/logic/secrets/`, `apps/web/auth/spec/integration/full/`,
  `spec/integration/...`).
- **concurrency** — multi-PROCESS harness (the C1 PoC under `../poc/`). A single MRI process cannot
  reproduce the reveal race (GIL); the in-process thread variant is a weaker secondary check only.
- **e2e** — Playwright under `e2e/` (CSP enforcement, clickjacking, SSO callback in-browser).

## Top cross-cutting risks (see each plan for the full list)

1. **A2 reverses a shipped behaviour and an existing passing spec.**
   `apps/web/auth/spec/unit/detect_mfa_requirement_spec.rb` currently asserts SSO bypasses MFA
   (`sso_bypass`, issue #3114). The A2 fix makes that wrong; those examples must be rewritten in the same
   PR (prescribed as SSO-U-08..12) or CI goes red. **Highest-attention item.**
2. **Concurrency tests need a clustered Puma + real Valkey in CI.** Run single-process and C1's race
   tests pass vacuously (false green). Prove they reproduce (fail today, 12/12) before the fix lands.
3. **ERB-at-boot env timing (S1/S2 and SSO integration).** Defaults and SSO route registration are baked
   from ENV at boot. Toggle tests must reboot inside the env block (`ClimateControl` +
   `Onetime.boot!(:test, force: true)`); SSO integration needs `ORGS_SSO_ENABLED=true` at process start
   or every example self-skips.
4. **Prescribed-but-unspecified surfaces.** `consume!` return shape (Lua vs WATCH),
   `resolve_omniauth_email`/`email_claim_verified?` provider table, `trust_idp_mfa`/`amr`/`acr` inputs,
   CSP Report-Only flag name, and the explicit-link `auth_error` code are not finalized in the resolutions.
   The plans assert behaviour and call out the exact spots to re-pin once the code lands.
5. **No v3 secret logic exists today** — "v1/v2/v3 reveal parity" reduces to v1+v2 through the shared
   model primitive; a placeholder gap tracks future v3.

## Reference inputs

- Resolutions: `../resolutions/{C1,S1,S2,A1,A2,A4}-*.md`
- PoC harness: `../poc/{_setup_secret.rb,_reveal_worker.rb,race_reveal.sh,race_reveal_model.rb,headers_check.rb}`
- Evidence: `../evidence/{race_poc_output.txt,headers_output.txt}`
- Mirrored specs: `apps/api/v2/spec/logic/secrets/burn_secret_spec.rb`,
  `apps/web/auth/spec/integration/full/omniauth_missing_email_spec.rb`,
  `apps/web/auth/spec/config/features/mfa_spec.rb`,
  `apps/web/auth/spec/unit/detect_mfa_requirement_spec.rb`,
  `spec/integration/full/env_toggles/security_features_spec.rb`,
  `e2e/auth/sso-missing-email.spec.ts`, `e2e/all/secret-context.spec.ts`
