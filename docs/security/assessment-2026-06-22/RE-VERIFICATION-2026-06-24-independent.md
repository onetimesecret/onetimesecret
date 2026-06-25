# Independent (Blind) Re-Verification — Pass 2 — of the 2026-06-22 Security Assessment

**Date:** 2026-06-24  **Reviewer:** second independent pass (blind re-derivation)
**Relationship to `RE-VERIFICATION-2026-06-24.md`:** that first pass is the comparison baseline; this
document does **not** replace it. Its headline is the **delta** — where this blind pass diverges from the
first, with every countable disagreement resolved by re-running the grep/read, plus the first pass's
flagged-open items closed.
**Stack:** Ruby 3.4.9; familia 2.11.0, otto 2.3.1, rodauth 2.42.0, rodauth-omniauth 0.6.2, oauth2 2.0.18,
rhales 0.7.1 (all as locked). Local Valkey.

---

## 1. What is different about this pass (and why it was worth running)

The first re-verification (2026-06-24) admitted its own structural weakness: *"the recheck was framed to
challenge-and-qualify, so this is corroboration, not an independent re-derivation."* This pass fixes exactly
that:

- **Stage 1 (verify) is BLIND** — each of the 39 findings was re-derived from scratch against the actual
  source and installed gems, with **no access to any prior conclusion**. Citations, vuln reality,
  default-reachability, fix soundness, severity — all derived cold.
- **Stage 2 (refute) defaults to OVERTURNING** — a genuinely adversarial agent, told the finding is wrong
  until proven right, re-opening the files itself.
- **Stage 3 (reconcile) is divergence detection with ground truth** — only here is the prior verdict
  introduced. Every countable disagreement (caller counts, line numbers, file existence, config defaults)
  was re-run by command and reported as ground truth, never picked between two claims.

39 findings × 3 stages. 113 agents completed on the first run; **P1** and **A5** failed on transient API
errors (stream timeout / structured-output retry cap) and were re-run separately. The four most
consequential corrections were then **hand-verified by me directly** (§3).

**The payoff:** a blind re-derivation finds things a challenge-and-qualify pass cannot. This pass surfaced
**seven fix problems the first pass rated "sound"** (§5), impeached a load-bearing **evidence file** (§5,
S2), **closed all of the first pass's open items** with hand-confirmed ground truth (§4), and — importantly
— **caught an overcorrection in its own output** (§3, A3) that hand-verification reversed. The result is more
trustworthy than either pass alone, in both directions: it does not rubber-stamp the assessment, and it does
not rubber-stamp itself.

---

## 2. Bottom line

The assessment remains **substantively trustworthy**: 0 fabricated citations, every finding maps to a real
code weakness. But this pass is materially more critical than the first on the **fix prescriptions** and
**severity calibration**, and it corrects several reachability claims in **both** directions.

- **Vuln reality:** all 39 are real. This pass re-labels ~16 as `real_but_latent` (mechanism present, no
  reachable production sink today) rather than `confirmed` — a precision refinement, not a downgrade of the
  underlying defect.
- **Fix soundness is the weak spot.** Of the resolution docs, this pass rates **3 unsound** (P4, **A8**,
  **P1**), **4 incomplete/regressing** (AZ2, AZ3, AZ7, **A5**), and ~20 `sound_with_caveats`. Only a handful
  are clean. **A8 and A5 are the most important new results: the first pass called both fixes `sound`;
  A8 is a no-op** on the default/primary databases and **A5's HMAC fix kills recovery codes on the primary
  flow** (§5). Because these are the boldest divergences, **both were hand-verified against the rodauth
  source**, not taken on agent word (§3e–§3f).
- **Severity recalibrations proposed:** A4 High→Medium, D1 High→Medium, S1 High→Medium; AZ1/AZ3/AZ4/AZ5
  Medium→Low; P2 and D2 effectively Low. A1 stays Critical, C1 stays High, S2 stays High.
- **23 of the first pass's corrections were independently reproduced blind** — the strongest possible
  confirmation that those corrections were real (P4-unsound, AZ8-regresses, AZ3-regresses, AZ2-wrong-sink,
  D1-wrong-chain, the AZ1/AZ4/S3 default-flag errors, and more).

---

## 3. The six hand-verified findings (not taken on agent word)

The advisor's rule — re-verify by command when this pass diverges from the prior in a severity-relevant
direction — caught the single most important error in *this* pass's own output.

### 3a. A3 — this pass's reconcile agent OVERCORRECTED; reverted to reach=FALSE (prior was right)

This pass's A3 reconcile agent flipped default-reachable to **TRUE**, reasoning that `authentication.enabled`
defaults true (`config.defaults.yaml:240`, `AUTH_ENABLED != 'false'`) and `reset_password` is enabled
unconditionally. **Hand-verification shows that is wrong**, and it is the *same* error class the agent
accused the prior pass of:

- `authentication.mode` defaults to **`simple`** (no `mode:` key under `authentication:` in the defaults →
  `auth_config.rb#mode` returns `'simple'`).
- `registry.rb:158-160`: `unless Onetime.auth_config.full_enabled? { reject web/auth/ }` — the **entire
  Rodauth auth app is not mounted in simple mode**. `full_enabled? == (mode == 'full')`.
- Therefore the A3-cited sink (`apps/web/auth/config/email/reset_password.rb` → Rodauth `base_url` →
  `request.host`) is **full-mode-only**, i.e. **NOT default-reachable**.

**Verdict: A3 reach = FALSE** (the prior pass and the risk register were correct). A3 remains a real **High**
weakness *when full auth is enabled*. **The default-mode reset path was also checked and is safe by
construction** (hand-verified): in `simple` mode **Core** handles password reset (`routes.txt:32` →
`Core::Controllers::Registration#request_password_reset_email` →
`apps/api/account/logic/authentication/reset_password_request.rb`), which enqueues the `:password_request`
email **without** a `baseuri` override; the mail view therefore falls back to `site_baseuri`, built from
`conf_dig('site','host')` (canonical config), **not** `request.host` (`lib/onetime/mail/views/base.rb:401-406`).
So the default reset link is **not** host-header poisonable. A3 is genuinely not default-reachable on either
path — and the simple-mode path is hardened, not merely unmounted.

**The discriminator (applies to every reachability call).** `web/auth` (the Rodauth account app — signup
UI, password-reset email, MFA, SSO, lockout) is **not mounted unless `mode == 'full'`** (`registry.rb:158`),
so A1/A2/A3/A4/A5/A6/A7/A8 are correctly **not default-reachable**. By contrast the **`/api/*` apps are
always mounted**, and `account_creation_allowed?` (`auth_strategies.rb:49-54`) gates `sessionauth`/`basicauth`
purely on `site.authentication.enabled == true` (mode-independent, default on) — so cookie-session and
basic-auth API endpoints **do** exist out of the box. This is exactly why **P1's reach=partial is correct
(hand-verified) while A3's reach=true was wrong**: same "auth on by default" premise, but P1's sink is on the
always-mounted `/api` surface and A3's is in the full-mode-only `web/auth` app.

### 3b. AZ2 — `serialize_organization` located; the first pass's open item is CLOSED

The first pass could not find the stripper and relayed the claim. Hand-confirmed at
`apps/api/organizations/logic/base.rb:61-80`:
- `record[:id] = record[:objid]` (`:66`) — **objid still leaks** as the `id` alias.
- `owner_extid` substituted (`:72`), then `record.delete(:owner_id)` (`:74`) — **the finding's `owner_id`
  headline is STALE; it is already stripped.**
- Residual member-visible leak rides `created_by`, `contact_email`, `billing_email` (none stripped) + the
  objid alias. The fix must edit `serialize_organization`, **not** the non-existent raw-`safe_dump`
  success_data the doc depicts; and removing `:objid` breaks the frontend zod contract + `O-Organization-ID`
  interceptor. Verdict: **fix incomplete_regresses** (first pass: sound_with_caveats).

### 3c. AZ8 — definitive caller count is 7 (first pass said 5, its sub-agent said 2)

Hand-confirmed **7** `Customer.create!` callsites passing `role:`/`verified:` as literal kwargs:
`create_customer.rb:62`, `sync_session.rb:175`, `apitoken_command.rb:168` **and `:190`**,
`customers/create_command.rb:97` **and `:121`**, `dev_basic_auth_strategy.rb:182`. The first pass's "5"
counted files, not callsites (missed the second `create!` in two CLI files). A name-based forbidden-raise
breaks all 7 — so the prescribed fix is **incomplete_regresses**; the sound fix is an opt-in
`allow_privileged:` kwarg gate (see §6).

### 3d. C1 — code-only re-confirmation (PoC deliberately not re-run)

Citations resolve in familia 2.11.0 (`secret_state_management.rb:60-89` in-memory guard then unconditional
`destroy!`; `persistence.rb:558`/`database_commands.rb:252-256` no WATCH/precondition). Option A's `consume!`
is a single-`EVAL` single-winner (the `dbclient.eval(keys:, argv:)` keyword form is real and in-app use).
Caveat the first pass missed: Option A's "rebuild ciphertext from fields" under-specifies the encrypted-field
**AAD context** — the correct realization decrypts the already-loaded in-memory winner, not raw `HGETALL`.
Verdict: **sound_with_caveats**. Runtime evidence (`evidence/race_poc_*`) stands; not re-run.

### 3e. A8 — "fix is a no-op" CONFIRMED against rodauth source

The boldest divergence (first pass: `sound`). All three required facts verified in rodauth-2.42.0:
`set_deadline_values?` is `db.database_type == :mysql` (`base.rb:750-752`); `set_deadline_value` writes
`hash[column]` **only inside `if set_deadline_values?`** (`base.rb:920-926`); `account_lockouts_deadline_interval`
is consumed at exactly one site (`lockout.rb:172`); and the non-MySQL `account_lockouts.deadline` column carries
`default: Sequel.date_add(CURRENT_TIMESTAMP, days: 1)` (`001_initial.rb:47-53`, `deadline_opts[1]`). So on
SQLite (default) and Postgres the deadline comes from the **DB column default** and the interval override does
nothing. **Fix = unsound, confirmed.**

### 3f. A5 — "double-HMAC kills recovery codes" CONFIRMED against gem + resolution doc

The other bold divergence (first pass: `sound`). Verified: `recovery_codes` is an `auth_cached_method`
(`recovery_codes.rb:49`) returning stored DB values; the OTS hook `mfa.rb` emits
`json_response[:recovery_codes] = recovery_codes` on `after_otp_setup` auto-add. The resolution doc overrides
**only** `add_recovery_code` (store HMAC) and `recovery_code_match?` (compare HMAC), and routes cleartext
display through a stash **"for the add-recovery-codes response only"** — it never rewires the OTS
`after_otp_setup` path, which keeps emitting the now-HMAC'd readback to the user → submitted value is HMAC'd
again → **recovery codes dead on the primary OTS flow.** **Fix = incomplete_regresses, confirmed.**

---

## 4. Open items from the first pass — all CLOSED with ground truth

| Open item | Closed answer (command-verified) |
|---|---|
| **AZ2** `serialize_organization` sink | Exists `base.rb:61-80`; strips `owner_id` (stale headline), leaks `created_by`/PII + objid-alias. §3b |
| **AZ8** caller count | **7** callsites / 5 files (not 2, not 5). §3c |
| **AZ1** default-flag | Register **No** correct, doc header **Yes** wrong. Prior *conclusion* right; prior *rationale* ("auth off") wrong — auth is on, the divergence is gated by **billing** off (STANDALONE_ENTITLEMENTS includes `manage_members`). |
| **AZ4** default-flag | Register **No** correct (`config.defaults.yaml:529` orgs default off); doc header **Yes** wrong. No reachable owner-escalation path (triple-guarded at the sole caller). |
| **S3** default-flag | Register **Yes** correct (`guest_routes.reveal` default true `:193`, CSP off `:353`); doc header **No** is misleading. Stock install IS affected. |
| **AZ3** `planid` mispoint + `is_default` regression | `planid` declared at `with_organization_billing.rb:34`, **not** `organization.rb:87` (an init default). Splat callers passing `is_default:true`: **3 production + 6 spec** (incl. `lazy_organization_creation_spec.rb`, which no prior input named). Fix = add `is_default` to allowlist. §6 |
| **D1** transitive chain | oauth2 pulled by `omniauth-oauth2`/`omniauth-google-oauth2` (Gemfile.lock:290/294), **not** `rack-oauth2` (a different gem). `2.0.22` is permitted by `~> 2.0` (installed 2.0.24 satisfies it). |
| **P4** dummy/timing | `Customer.dummy` sets **no** apitoken → `apitoken?` short-circuits at `customer.rb:263` before `secure_compare`; V1 uses `Rack::Utils.secure_compare` (sub-µs), **not** BCrypt. Fix unsound; dummy must carry a real token. |
| **A1** pure-SSO gap | `resolve_omniauth_email` does **not** exist yet (0 hits); the proposed `account_has_other_authenticators?` returns false for pure-SSO accounts → cross-provider takeover of a pure-SSO victim is **not** closed by the design as written. |
| **P1** SameSite / env-key / blanket exemption | Session cookie default **is** `SameSite=Lax` (`boot.rb:80-85`, `config.defaults.yaml:293`); `env['otts.auth_method']` is **never populated** (0 hits, wrong layer); `/api/` exemption **is** blanket (`security.rb:142`). `sessionauth` is registered by default (mode-independent) → reach=partial. |

---

## 5. New problems this pass found that the first pass MISSED

These are the value-add — the first pass rated each "sound" (or didn't analyze it).

- **A8 — fix is UNSOUND (first pass: `sound`).** Overriding `account_lockouts_deadline_interval` is a
  **no-op on SQLite (default) and Postgres**: the 1-day deadline comes from the **DB column default**, and
  `set_deadline_value` writes the interval only when `set_deadline_values? == (db type == :mysql)`
  (`base.rb:750-752, 920-926`; migration `001_initial.rb:47-53`). A complete fix must override
  `set_deadline_values?` to true (single source of truth) or pair a column-default migration *with* the
  interval for MySQL. The doc's exponential-backoff block is dead-on-arrival on every backend.
- **A5 — fix is INCOMPLETE_REGRESSES (first pass: `sound`).** The HMAC fix overrides recovery-code store +
  compare but **not** the `auth_cached_method` readback (`recovery_codes.rb:49`), so `mfa.rb:248`
  (`after_otp_setup` auto-add) emits the **HMACs** to the user → the user submits an HMAC → it gets HMAC'd
  again → **double-HMAC, recovery codes dead on the primary OTS flow**. The migration also rewrites `code`,
  which is half the composite PK `[:id, :code]` (`001_initial.rb:197`) — must delete+insert per row, not
  `UPDATE` in place. Fix: route display through a request-scoped cleartext stash; keep stored values HMAC'd.
- **P1 — fix is UNSOUND (first pass: `sound_with_caveats`).** Three independent failures against
  rack-protection 4.2.1: `:except_when` is **not a recognized option** (only `:allow_if`); wrong lambda
  **arity** (the gem calls `allow_if.call(env)` single-arg, the sketch is `->(req, env)`); and
  `env['otts.auth_method']` is **never populated** and unreadable at middleware time (the Security middleware
  runs before post-routing auth resolves). Reach also corrected `false`→**partial** (hand-verified §3a):
  `sessionauth` is registered by default, so cookie-auth `/api` mutation endpoints exist; SameSite=Lax blocks
  the headline cross-site POST, leaving same-site-subdomain / legacy-browser residuals. Corrected fix:
  discriminate inside the existing single-arg lambda — exempt only requests with no `onetime.session` cookie
  or an explicit `Authorization` header; enforce `X-CSRF-Token` otherwise (the SPA already sends it).
- **S2 — the "Confirmed live" evidence is methodologically INVALID.** `evidence/headers_output.md` has
  **no valid HTML-200 capture**: the only 200 is `GET /api/v2/status` (JSON — `X-Frame-Options` never fires
  on JSON, even after a fix), and the only HTML-path request (`GET /`) **500'd from a harness bug**
  (`Rack::Lint`: `HTTP_USER_AGENT` nil). The S2 vuln still stands on code analysis, but the empirical proof
  the first pass accepted does not exist. (The same file is the S1/S2 evidence cited across the docs.)
- **S1 — fix is SCOPE-INCOMPLETE (first pass: `sound`).** Flipping `CSP_ENABLED` only makes the **API v1
  JSON app** emit CSP (`helpers.rb:212`, the sole writer). The **secret-display HTML pages** (`/secret/*`,
  `/` → `Core::Controllers::Page#index`) have **no CSP write path** (otto's `send_csp_headers` is never
  called). The doc's own stated goal — protect the page that shows the secret — is not met by the flag flip.
- **D3 — fix step 2 is NON-IMPLEMENTABLE (first pass: `sound`).** The CI host-side `*.map` delete "after
  Sentry upload, before packaging" has no such window: the image is **built+pushed before** the Sentry step,
  and the targeted `public/web/dist` is gitignored/absent host-side. Strip maps **inside** the Dockerfile
  build stage instead.
- **AZ5 — fix ships an always-on DEPLOY HAZARD (first pass: `sound`).** `EXTID_HMAC_SECRET` is never bridged
  (`configure_familia.rb:55` bridges only the verifiable-id secret), and `Organization.create!` runs on
  **every signup** (not orgs-gated), wrapped in a `rescue → nil` swallow. An unprovisioned deploy silently
  breaks default-workspace creation. Add the env bridge + deploy ordering; also Customer/CustomDomain share
  the unkeyed pattern (org-only fix is incomplete).
- **P3 — fix UNDER-COUNTS (first pass: `sound`).** `record_secret_creation! if greenlighted` records only on
  success, so failed/abusive creation floods burn no quota. Count at attempt time.
- **AZ7 — escalated to INCOMPLETE_REGRESSES (first pass: `sound_with_caveats`).** Backend-only edits break
  the frontend: `AcceptInvite.vue:134` `.parse()` requires `invited_by_email` + `account_exists` (the latter
  also drives the signin/signup branch at `:97`). Must ship frontend changes in lockstep.
- **A2 — fix `sound_with_caveats` + a sub-claim is FALSE.** The "SSO silently overrides
  `mfa_policy == :required`" aggravator is **dead code** — `mfa_policy` is never populated in production
  (`detect_mfa_requirement.rb`); the lone caller omits it. The bypass-for-enrolled-accounts is real; the
  named `:required` override is not. The fix sketch also violates the operation's documented pure-function
  contract.
- **Compile-level defects in fix snippets:** **AZ9** (`client_ip`/`domain_key` used cross-method →
  NameError), **A6** (bare `env` not in scope → NameError; `allowed_webauthn_host?` doesn't exist),
  **S2** (HSTS flag flips emit on plain HTTP; `http_origin` flip `:deny`s legit cross-origin POSTs),
  **C4** (`defined?(RSpec)` boot guard raises under Tryouts → breaks the whole suite).

---

## 6. Corrected fixes (the actionable rewrites)

Full text per finding lives in the working detail; the load-bearing ones:

- **AZ3 — one-line fix:** `CREATE_ALLOWED_ATTRS = %i[display_name description is_default].freeze`. `is_default`
  is a workspace flag (delete-protection / same-customer domain-SSO), not a billing field — safe to
  allowlist; `planid`/`complimentary`/`stripe_*` stay excluded (the real goal). Correct the doc's "owned by
  trusted internal flows" comment.
- **AZ8 — opt-in gate (Option B, lowest churn):** in `Customer.create!`, `kwargs.delete(:allow_privileged)`;
  unless set, raise if any of `%i[role verified verified_by]` present. Add `allow_privileged: true` to the 7
  legitimate callers. A future `create!(**raw_params)` carries no flag → attacker `role:'colonel'` raises.
  (Name-based "special-case the literals" is impossible — literal and forwarded `'customer'` are identical.)
- **AZ2 — edit `serialize_organization`:** delete `:identifier`/`:created_by` from the member baseline; keep
  `owner_id` deletion; **defer `:objid` removal** behind a coordinated interceptor+store+contract migration
  (it is a hard runtime dependency); nil-out (don't delete) `contact_email`/`billing_email` for non-admins
  (contract requires the key present); author the missing `entitlement_in?` helper; gate the `members[]`
  array (`get_organization.rb:54-60` emits `member.objid` + email).
- **P4 — give the dummy a real token:** in `Customer.dummy`, `apitoken = SecureRandom.hex(32)` before
  `freeze`, so a wrong guess reaches `secure_compare`. Residual: `load_by_extid_or_email` still
  deserializes on hit vs nil on miss — optional defense-in-depth, noise-dominated.
- **A8, S1, D3, AZ5, P3, A2, A6, AZ9, C4, S2:** see §5 — each has a concrete corrected prescription in the
  per-finding detail.

---

## 7. Severity & default-reachability recalibrations

| ID | This pass | Rationale (ground-truth) |
|---|---|---|
| A4 | High → **Medium** (standalone) | High only via the A1 takeover chain, which A1 already carries as Critical — double-count. Standalone = self-account policy bypass. |
| D1 | High → **Medium** | Only fixed trusted endpoints (Google/GitHub/Entra) reach the oauth2 sink; the tenant-injectable OIDC issuer path uses `rack-oauth2`, not the vulnerable gem. |
| S1 | High → **Medium** | Defense-in-depth, no demonstrated XSS sink; nonce infra wired; and the flag-flip fix doesn't even cover the secret pages. |
| P1 | High → **Medium**; reach false → **partial** | Blanket `/api/` token-CSRF exemption over cookie-auth mutations is real (> Low), but SameSite=Lax default blocks the headline cross-site POST (< High). `sessionauth` on `/api` is default-on (§3a discriminator). |
| P2 | Medium → **Low** (default) / Medium (domains on) | Register row "Default: Yes" overstates — needs a private/loopback/SSRF vantage AND `domains.enabled` (default off). |
| D2 | Medium → **Low** (practical) | Native browser FormData + hardcoded field name + `node_modules` deleted at runtime. Finding-detail's **HIGH** header self-contradicts the register's Medium. |
| AZ1/AZ3/AZ4/AZ5 | Medium → **Low** | Latent, default-off, no reachable sink; AZ1/AZ4 caller-guarded. |
| A3 | High holds; **reach FALSE** | §3a — cited sink is full-mode-only. |
| A1 / C1 / S2 | unchanged (Critical / High / High) | Confirmed. |

---

## 8. Meta-findings (reaffirmed from the first pass)

1. **"Fork" mislabel is cosmetic.** `rodauth` (2.42.0) and `rodauth-omniauth` (0.6.2) resolve to upstream
   rubygems with no `path:`/`git:` override; ~20 findings cite "fork" files that are stock gems. No finding
   is undermined — every auth/SSO vuln is correctly attributed to OTS config. Correct the header wording.
2. **Citation drift is minor and never fabricated** — abbreviated gem paths, ±a few lines, the odd mispoint
   (`planid`, A8 `before_login_attempt` ~9 lines). Every load-bearing construct resolves.
3. **Systemic clarification — there are TWO auth surfaces, gated differently.** `authentication.enabled`
   defaults **true**, but `authentication.mode` defaults **`simple`**. The two surfaces:
   - **`web/auth` (Rodauth full account system: signup UI, password-reset email, MFA, SSO, lockout)** —
     mounted **only in `full` mode** (`registry.rb:158`). Off by default. This is why A1/A2/A3/A4/A5/A6/A7/A8
     are correctly *not* default-reachable, and why this pass's A3 agent erred by reading only `enabled`
     (§3a). In `simple` mode, **Core** provides a lighter `/auth/*` implementation.
   - **`/api/*` apps (sessionauth + basicauth)** — always mounted; `account_creation_allowed?`
     (`auth_strategies.rb:49-54`) gates the session/basic strategies on `authentication.enabled` alone
     (**mode-independent**). So cookie-session and API-key auth on `/api` **are** on by default.
   This split is the correct way to read every reachability call: it is why **P1 = partial** (its sink is on
   the always-mounted `/api` surface) while **A3 = false** (its sink is full-mode-only `web/auth`). The
   first pass's blanket "auth off by default" was directionally right for the account system but wrong for
   the API surface; the precise statement is the two-surface split above.
   - *Consistency note:* **P4** (V1 basic-auth timing) is on the same always-mounted API surface, so its
     `reach=false` is conservative — the basic-auth path is registered by default just like `sessionauth`.
     The verdict is unaffected (Low, timing-only, fix unsound), but for method-consistency P4's
     reachability is better read as the same default-on/partial as P1.

---

## 9. Per-finding verdict matrix (this pass)

`vuln / default-reachable / fix / severity`. `Div` = count of divergences from the first pass. `Repro` =
this blind pass independently reproduced a first-pass correction.

| ID | vuln / reach / fix / severity | Div | Repro | Conf |
|---|---|---|---|---|
| A1 | real_but_latent / false / sound_with_caveats / Critical | 2 | . | high |
| C1 | confirmed / true / sound_with_caveats / High | 2 | . | high |
| A2 | confirmed / false / sound_with_caveats / Low-Medium | 3 | . | high |
| A3 | confirmed / **false** (corrected §3a) / sound_with_caveats / High | 1 | Y | high |
| A4 | confirmed / false / sound_with_caveats / **Medium** (standalone) | 2 | Y | high |
| P1 | real_but_latent / **partial** / **unsound** / **Medium** | 5 | Y | high |
| S1 | confirmed / true / **sound_with_caveats** / **Medium** | 3 | . | high |
| S2 | confirmed / true / sound_with_caveats / High | 3 | Y | high |
| D1 | confirmed / false / sound / **Medium** | 2 | Y | high |
| C2 | confirmed / true / sound / Medium | 2 | Y | high |
| C3 | confirmed / true / sound_with_caveats / Medium | 0 | Y | high |
| P2 | confirmed / false / sound_with_caveats / **Low** (default) | 5 | Y | high |
| P3 | confirmed / true / **sound_with_caveats** / Medium | 1 | . | high |
| AZ1 | real_but_latent / false / sound / **Low** | 6 | Y | high |
| AZ2 | confirmed / partial / **incomplete_regresses** / Medium | 4 | Y | high |
| AZ3 | real_but_latent / false / **incomplete_regresses** / **Low** | 4 | Y | high |
| AZ4 | real_but_latent / false / sound_with_caveats / **Low** | 3 | Y | high |
| AZ5 | real_but_latent / false / **sound_with_caveats** / **Low** | 4 | . | high |
| A5 | confirmed / false / **incomplete_regresses** / Medium | 5 | . | high |
| A6 | real_but_latent / false / sound_with_caveats / Medium | 0 | Y | high |
| A7 | confirmed / false / sound_with_caveats / Medium | 1 | Y | high |
| A8 | confirmed / false / **unsound** / Medium | 5 | . | high |
| D2 | real_but_latent / false / sound / **Low** (practical) | 3 | . | high |
| D3 | confirmed / true / **sound_with_caveats** / Medium | 3 | Y | high |
| D4 | real_but_latent / partial / sound_with_caveats / Medium | 4 | . | high |
| D5 | confirmed / true / sound_with_caveats / Medium | 2 | Y | high |
| S3 | confirmed / true / sound_with_caveats / Medium | 1 | . | high |
| C4 | confirmed / partial / sound_with_caveats / Low–Medium | 2 | Y | high |
| C5 | confirmed / true / sound_with_caveats / Low | 0 | Y | high |
| C6 | real_but_latent / partial / sound_with_caveats / Low (info) | 4 | . | high |
| AZ6 | confirmed / true / sound_with_caveats / Low | 3 | . | high |
| AZ7 | confirmed / partial / **incomplete_regresses** / Low | 4 | Y | high |
| AZ8 | real_but_latent / false / **incomplete_regresses** / Low | 2 | Y | high |
| AZ9 | real_but_latent / false / sound_with_caveats / Low | 2 | Y | high |
| P4 | real_but_latent / false / **unsound** / Low | 5 | Y | high |
| P5 | real_but_latent / false / sound_with_caveats / Low | 3 | Y | high |
| S4 | real_but_latent / false / sound_with_caveats / Low | 3 | Y | high |
| S5 | real_but_latent / false / sound_with_caveats / Low | 2 | . | high |
| OBS1 | real_but_latent / false / sound / Info | 0 | . | high |

_39 findings; blind verify → adversarial refute → ground-truth reconcile. 119 agents (113 + 6 P1/A5 re-run).
Eight load-bearing facts hand-verified directly against source: A3 reach (both paths), AZ2
`serialize_organization` sink, AZ8 caller count, P1 `sessionauth` reach, C1 atomicity, **A8 no-op**,
**A5 double-HMAC**, and the simple/full auth-mount split — including one reversal of this pass's own A3 output.
The two boldest new divergences (A8, A5) were deliberately the most verified, not the least._
