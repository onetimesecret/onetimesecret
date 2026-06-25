# Independent Re-Verification of the 2026-06-22 Security Assessment

**Date:** 2026-06-24 **Reviewer:** independent re-verification pass (audit-grade)
**Scope:** all 38 findings of `docs/security/assessment-2026-06-22/` — citation accuracy, vulnerability
reality, fix soundness, and severity calibration.
**Stack under verification:** Ruby 3.4.9; **familia 2.11.0, otto 2.3.1, rhales 0.7.1** (bumped from
2.10.1 / 2.3.1 / 0.6.2 at the maintainer's request); rodauth 2.42.0, rodauth-omniauth 0.6.2, oauth2 2.0.18
(all as locked). Local Valkey.

> **Method.** Each finding was re-checked by an independent agent (resolve every `file:line` citation
> against the actual source — app code, and library code in the *installed gems*; confirm the weakness is
> real and reachable; judge the prescribed fix; calibrate severity), then a second adversarial agent tried
> to **overturn** that verdict with code evidence. 76 agents total. The headline finding (**C1**) was
> additionally re-verified at runtime by booting the real application stack and reproducing the race.

---

## 1. Bottom line

**The assessment is substantively trustworthy.** It is not AI confabulation: across 38 findings,

- **0 fabricated or badly-mispointed citations.** Every cited construct resolves in the actual source
  (app or installed gem). Drift is limited to ±a few lines and abbreviated paths; the single genuine
  mispoint is minor (AZ3's `organization.rb:87`, an init default rather than the field declaration).
- **38/38 weaknesses are real.** 30 confirmed outright; 8 are *real-but-latent* (mechanism present, but
  no reachable production sink today, or a precondition must hold) — none is a false positive.
- **No verify verdict was overturned** by the adversarial recheck — but the recheck was framed to
  challenge-and-*qualify*, so this is corroboration, not an independent re-derivation of every verdict;
  in a few cases (AZ8, A1) it *strengthened* the criticism. **The four most consequential §4 corrections
  (P1, P4, AZ8, AZ3) were additionally re-checked by hand** (direct file reads), not taken on sub-agent word.
- **C1 — the headline — independently reproduced at runtime on familia 2.11.0:** 10/10 (model barrier)
  and **12/12 independent OS processes obtained the same one-time secret's plaintext**; the key was then
  consumed. The prescribed fix (Option A) is genuinely atomic.

The re-verification's contribution is therefore **refinement, not refutation**: two severity downgrades,
nine default-config-flag corrections, and five resolution-docs whose *prescribed fix* would misfire if
implemented verbatim. These are listed in §3–§4.

### Severity tally (re-verified)
1 Critical (A1), 8 High (one — P1 — recommended down to Medium; one — P2 — keeps severity but loses its
default-config claim), ~16 Medium, ~12 Low/Info. The assessment's own tally holds.

---

## 2. Per-finding verdict matrix

`Severity check`: upheld / overstated(→proposed). `Default flag`: does the doc's "affects default config?"
match reality. `Vuln`: confirmed / partial(real-but-latent). `Dflt-reachable`: exploitable in the
out-of-the-box config (auth + SSO + diagnostics OFF). `Fix`: soundness of the *prescribed* resolution.
`Recheck`: adversarial outcome (`none` = verify verdict survived).

| ID | Claimed | Severity check | Default flag | Citations | Vuln | Dflt-reachable | Fix | Recheck |
|---|---|---|---|---|---|---|---|---|
| A1 | Critical | upheld | correct | minor_drift | confirmed | False | sound_with_caveats | none |
| C1 | High | upheld | correct | all_accurate | confirmed | **True** | sound | none |
| A2 | Low-Med | upheld | correct | all_accurate | confirmed | False | sound | none |
| A3/P2 | High | **A3 holds; P2 default overstated** | partial | all_accurate | confirmed | False | sound_with_caveats | none |
| A4 | High | upheld | correct | all_accurate | confirmed | False | sound_with_caveats | none |
| P1 | High | **overstated → Medium** | correct | all_accurate | partial | False | sound_with_caveats | none |
| S1 | High | upheld | correct | minor_drift | confirmed | **True** | sound | none |
| S2 | High | upheld | correct | minor_drift | confirmed | **True** | sound_with_caveats | none |
| D1 | High | upheld | correct | all_accurate | confirmed | False | sound | none |
| C2 | Medium | upheld | correct | all_accurate | confirmed | True | sound | none |
| C3 | Medium | upheld | correct | minor_drift | confirmed | True | sound_with_caveats | none |
| P3 | Medium | upheld | correct | all_accurate | confirmed | True | sound | none |
| AZ1 | Medium | upheld | **incorrect (doc says Yes; No)** | all_accurate | confirmed | False | sound | none |
| AZ2 | Medium | upheld | correct | all_accurate | confirmed | False | **sound_with_caveats (wrong sink)** | none |
| AZ3 | Medium | upheld | correct | minor_drift | partial | False | **sound_with_caveats (regresses callers)** | none |
| AZ4 | Medium | upheld | **incorrect (doc says Yes; No)** | all_accurate | partial | False | sound_with_caveats | none |
| AZ5 | Medium | upheld | correct | all_accurate | confirmed | False | sound | none |
| A5 | Medium | upheld | correct | minor_drift | confirmed | False | sound | none |
| A6 | Medium | upheld | correct | minor_drift | partial | False | sound_with_caveats | none |
| A7 | Medium | upheld | correct | minor_drift | confirmed | False | sound_with_caveats | none |
| A8 | Medium | upheld | correct | minor_drift | confirmed | False | sound | none |
| D2 | Medium | upheld | correct | all_accurate | confirmed | True | sound | none |
| D3 | Medium | upheld | correct | all_accurate | confirmed | True | sound | none |
| D4 | Medium | upheld | partial (full-stack only) | all_accurate | confirmed | False | sound | none |
| D5 | Medium | upheld | correct | all_accurate | confirmed | True | sound | none |
| S3 | Medium | upheld | **incorrect (doc says No; Yes)** | all_accurate | confirmed | **True** | sound_with_caveats | none |
| C4 | Medium | upheld | partial (C4a yes / C4b no) | all_accurate | confirmed | True | sound | none |
| C5 | Low | upheld | correct | minor_drift | confirmed | True | sound | none |
| C6 | Low | upheld | correct | minor_drift | confirmed | True | sound | none |
| AZ6 | Low | upheld | correct | all_accurate | confirmed | True | sound | none |
| AZ7 | Low | upheld | partial | all_accurate | confirmed | True | sound_with_caveats | none |
| AZ8 | Low | upheld | partial | all_accurate | partial | False | **incomplete (regresses ≥5 callers)** | none |
| AZ9 | Low | upheld | correct | all_accurate | confirmed | False | sound | none |
| P4 | Low | upheld | correct | minor_drift | confirmed | False | **unsound** | none |
| P5 | Low | upheld | correct | all_accurate | confirmed | False | sound | none |
| S4 | Low | upheld | partial | all_accurate | confirmed | False | sound | none |
| S5 | Low | upheld | correct | all_accurate | partial | False | sound | none |
| OBS1 | Info | upheld | correct | all_accurate | confirmed | False | sound | none |

---

## 3. C1 — runtime re-verification (headline)

Re-ran the committed model PoC (adapted only for this worktree's `RACK_ENV=test` config resolution; logic
unchanged) and added a true multi-process reproduction, both against **familia 2.11.0**. Evidence:
`evidence/race_poc_reverify_2026-06-24.md`.

- **Model barrier PoC (deterministic):** 10 threads, **10/10** passed the `viewable?` gate and returned
  the plaintext; secret consumed. Matches the assessment's "deterministic 10/10."
- **True multi-process PoC (12 independent OS processes, no shared GIL, shared consume barrier):**
  **12/12 processes obtained the same secret's plaintext**; the Redis key was deleted (`EXISTS`→0).
  This independently reproduces the assessment's headline "12/12."
- **In-process full-stack PoC via the real `/api/v2/secret/:id/reveal` endpoint:** **1/25** — GIL-bound, as
  the assessment itself predicted. Confirms *why* a single MRI process masks the bug, not a refutation.

**Prescribed fix is sound and genuinely atomic.** Option A's `consume!` runs `HGET state → (if new/previewed)
HGETALL + DEL → return` inside a single Redis `EVAL`; Redis executes Lua atomically, so exactly one caller
can observe a consumable state and delete — the rest get `nil`. This is a single-winner op, not check-then-act.

> **Re: the "12/12 → 1/12" fix evidence (now committed at `evidence/c1_fix_verification.md`).** It was
> run on a separate fix worktree against `claim_consumption!` (the prescribed atomic consume). After the
> fix: `viewable=12/12` (all pass the non-authoritative pre-check) but **`won=1/12` and `got plaintext=1/12`**
> — *exactly one* caller wins and discloses. **That is the one-time guarantee holding, not a residual leak:**
> `1/12` = one legitimate reader; `0/12` would mean the secret is unreadable by anyone. So the prior
> handoff's reading of "1/12, not 0/12 → residual disclosure" was mistaken — `1/12` is the *success*
> criterion. Before the fix: 12/12 all leak; after: 1/12 single winner. The prescription closes the race;
> extending the same atomic consume to **burn** and the v1/v3 paths is correct.

**Cross-confirmation.** The original assessment's `evidence/race_poc_output.md` (familia 2.10.1) shows the
identical pattern to this pass's reproduction (familia 2.11.0): deterministic **10/10**, GIL-masked natural
race **1/N**, true multi-process **12/12**. Two independent runs on two familia versions agree — the headline
is not an artifact of one environment.

---

## 4. Corrections to apply (the actionable deltas)

### 4a. Severity / applicability over-statements (2)
- **P1 (CSRF for cookie-auth `/api/*`): recommend *reconsidering* High → Medium** (a judgment call, not a
  settled downgrade). **Confirmed by hand:** the session cookie defaults to **`SameSite=Lax`** in production
  (`lib/onetime/boot.rb` `SESSION_DEFAULTS`; `etc/defaults/config.defaults.yaml:293`), which blocks the
  described cross-site `POST`, and the path is unreachable in the default config (auth off → `sessionauth`
  never registered). **But** the residual same-site sibling-subdomain forgery vector and browser variance
  are why many reviewers keep an explicit CSRF exemption elevated regardless of SameSite — so treat this as
  "reconsider," not "downgrade." The finding itself (blanket `/api/` token-CSRF exemption) stands.
- **P2 (host-header forwarded-trust): keep Medium, drop the default-config claim.** An external attacker
  in the default config has a **public `REMOTE_ADDR`**, so `private_ip?` is false and forwarded Host is
  ignored (finding 04 itself concedes this). P2 needs a private/loopback/SSRF vantage — *not* out-of-the-box.
  **A3 is unaffected** and correctly High: auth-email links read raw `HTTP_HOST` directly.

### 4b. Prescribed fixes that misfire as written (5 — fix the resolution docs before implementing)
- **P4 — fix is UNSOUND.** `Customer.dummy` (`customer.rb:331-340`) never sets an apitoken, so
  `apitoken?` early-returns at `:263` *before* `secure_compare` runs — no timing parity is achieved.
  Compounding: the doc's "expensive BCrypt / ~280ms" premise is wrong; V1 uses cheap
  `Rack::Utils.secure_compare`. A sound fix must give the dummy a real non-empty token.
- **AZ8 — fix INCOMPLETE / regressing.** The prescribed `CREATE_FORBIDDEN_ATTRS` raise on
  `role`/`verified`/`verified_by` would break **five production callsites** that pass those as literal
  kwargs into `Customer.create!` — *enumerated by hand:* two in the auth flow
  (`apps/web/auth/operations/create_customer.rb:62`, `sync_session.rb:175`) and three in CLI/dev tooling
  (`lib/onetime/cli/customers/create_command.rb:97`, `cli/apitoken_command.rb:168`,
  `application/auth_strategies/dev_basic_auth_strategy.rb:182`). (The doc's "callers unaffected" claim
  checked only the create-flow path; the verify-stage agent undercounted to 2.) Migrate those callsites to
  post-create assignment, or special-case the literals. The vuln itself stays latent — no params-forwarding sink.
- **AZ3 — fix INCOMPLETE / regressing + one mispoint.** Allowlist omits `is_default`; the fail-closed raise
  would break the two splat callers (`plans.rb`, `welcome.rb`) that pass `is_default: true`. Also the
  "sole caller" claim is false (3+ callers) and `planid` is mis-cited to `organization.rb:87` (an init
  default; real declaration in `with_organization_billing.rb:34`). Vuln still latent (no params-forwarding sink).
- **AZ2 — finding confirmed; the fix's sink needs a second look (relayed, not hand-confirmed).** Direct
  read confirms `safe_dump` exposes `objid`, `owner_id`, `created_by`, `contact_email`, `billing_email` to
  any member (`organization/features/safe_dump_fields.rb:17-29`) — the leak is real and the finding stands.
  The sub-agent further claimed the member-facing leak actually rides on `created_by` via the API serializer
  (with `owner_id` stripped downstream), so the prescribed `safe_dump` minimization may target the wrong
  layer and could regress `id`/`owner_extid`/`role`. **I could not locate a `serialize_organization`
  stripper to confirm that refinement** — verify the actual member-facing serializer before editing `safe_dump`.
- **A1 — fix has a real residual gap (does not undermine the finding).** Layers 1–2 of the proposed
  `#3499`-folded fix do **not** close cross-provider takeover of a *pure-SSO* victim account by a malicious
  tenant IdP (the helper `account_has_other_authenticators?` returns false for such accounts). Also: the
  github `email_claim_verified?` is assumed `true` unconditionally, and the whole fix depends on `#3499`'s
  not-yet-landed `resolve_omniauth_email`. Design needs the pure-SSO case handled before SSO ships.

### 4c. Internal "affects default config?" contradictions (resolution-doc header vs. risk register)
Where they disagree, the register is generally the more defensible reading:
- **AZ1, AZ4:** resolution header says **Yes**, register says **No** — register correct (auth-OFF default
  makes these org endpoints unreachable). Fix the doc headers.
- **S3:** resolution header says **No**, register says **Yes** — **register correct** (any anonymous
  recipient reveal populates the SPA store; no flag needed). The vuln *is* default-reachable.
- **A3/P2, D4, C4, AZ7, AZ8, S4:** "partial" — the doc over- or under-generalizes a split (e.g., C4a is
  default-reachable but C4b needs a misconfigured `RACK_ENV=test`; D4 ships only in the full compose stack).

### 4d. Lower-priority fix caveats (sound, but note)
- **S4:** `DOMPurify.addHook` is global to the singleton — it cannot be "scoped to this component's
  sanitize call" as the doc suggests.
- **AZ7:** the inviter-attribution snippet reads a `Customer#display_name` that doesn't exist (doc hedges
  to "omit" — take that path).
- **A6:** pinning the WebAuthn RP-ID invalidates already-enrolled credentials (doc flags it; sequence
  after A3/P2).

---

## 5. Cross-cutting meta-findings (about the assessment itself)

1. **"Fork" framing is inaccurate (cosmetic).** The executive report's header calls `rodauth` and
   `rodauth-omniauth` "OTS forks," but this bundle resolves both to **upstream rubygems** (rodauth 2.42.0;
   rodauth-omniauth 0.6.2 = `janko/rodauth-omniauth`). 20 findings cite "fork" library files that are plain
   upstream. It does **not** undermine any finding — every auth/SSO vuln is correctly attributed to OTS's
   own config overrides — and the report's own §4 already says "rodauth-omniauth is unmodified upstream
   v0.6.2." Recommend correcting the header wording to "OTS auth *configuration* over upstream rodauth."
2. **The `evidence/` directory was missing because `.gitignore:5` ignores `*.txt` — now RESOLVED.** C1/S1/S2
   originally cited `evidence/*.txt`, which git silently excluded (a process trap, not an oversight: any
   future `evidence/*.txt` vanishes the same way). The original author has since committed the evidence as
   tracked **`.md`** (`310fe1a5e7`): `race_poc_output.md`, `c1_fix_verification.md`, `headers_output.md`, and
   fixed the references across the docs. **`headers_output.md` is the live S1/S2 proof** — `GET /api/v2/status`
   returns with `content-security-policy`, `x-frame-options`, and `strict-transport-security` all `<ABSENT>`.
   This pass's `evidence/race_poc_reverify_2026-06-24.md` is retained as the independent familia-2.11.0
   cross-check. Recommendation going forward: keep PoC evidence as `.md` (or `git add -f`).
3. **Citation drift is real but minor.** Abbreviated library paths (`features/lockout.rb:15`), directory
   slips (`logic/members/` vs `logic/invitations/`, `middleware_stack.rb` vs `application/middleware_stack.rb`),
   and ±2–9 line offsets are common but always resolve to the right construct. The only true mispoint is
   AZ3's `planid` citation.

---

## 6. Note on the dependency bump

To verify against the versions requested (familia 2.11.0, otto 2.3.1, rhales 0.7.1), `Gemfile` constraints
were updated (`familia ~> 2.11`, `rhales ~> 0.7.1`; otto already satisfied `~> 2.3`) and `bundle install`
re-locked offline. **familia 2.11.0 introduced no drift in the C1-relevant internals** (`persistence.rb`
`destroy!` and `database_commands.rb` `delete!` resolve exactly; the race reproduces). This is a working-tree
change on an otherwise docs-only branch — left uncommitted pending the maintainer's decision on whether to
land it separately from the security docs.

---

## 7. Per-finding detail

### A1 — confirmed, fix sound_with_caveats
A1 is a real, correctly-cited account-takeover vulnerability (SSO-gated, not default-config); the core OTS-config citations resolve exactly, severity Critical-when-SSO-on is upheld, and the proposed #3499-folded fix is sound with two caveats (github verified-assumption, dependency on unlanded resolve_omniauth_email); only meta-issues are the cosmetic 'fork' mislabel and a minor gem-path drift, neither undermining the finding.

Discrepancies:
- Path drift: finding cites rodauth-omniauth lib/rodauth/omniauth_base.rb but actual file is lib/rodauth/features/omniauth_base.rb (omniauth_email defined at 67-71 as omniauth_info['email']). Missing 'features/', no line number — minor drift, not a mispoint.
- Precision nuance (finding gets it right): for an already-OPEN victim account the takeover succeeds via account_from_omniauth→create_omniauth_identity→login regardless of the verify override; omniauth_verify_account? true only EXTENDS takeover to unverified/unopen accounts (the upstream guard is consulted only in the if account && !open_account? branch, gem line 69-70). This strengthens vuln_real.

### C1 — confirmed, fix sound
C1 is a real, correctly-cited TOCTOU race exploitable in the default anonymous-sharing config, and the prescribed Option A consume! is a genuinely atomic single-EVAL single-winner fix (Options B/C also sound); severity High upheld.

Discrepancies:
- Burn citation 'viewable? check at :55' is slightly loose — :55 computes `viewable = potential_secret.viewable?`; the construct is present, minor drift not an error.
- Resolution doc references 'v1/v3 reveal paths' but the codebase/finding-side docs only enumerate v1 and v2; the 'v3' label is loose but immaterial — both real paths (v1 show_secret.rb:71, v2 reveal_secret.rb:189) call secret.revealed!.

### A2 — confirmed, fix sound
A2 is accurately cited (all line ranges exact), the vuln/behavior is real and intentional (#3114, spec-asserted), the Low-Med reclassification is justified (SSO-as-authenticated is industry default, not default-reachable since SSO is off out-of-box), and the prescribed fix is sound and genuinely additive (opt-in toggle, default unchanged).

Discrepancies:
- Exec report line 112 says 'SSO bypasses MFA unconditionally' while resolution title softens to 'opt-in second factor'; both are consistent with code (bypass overrides even :required policy) — no contradiction, just framing shift after reclassification.

### A3/P2 — confirmed, fix sound_with_caveats
A3 and P2 are real and all finding/fix citations resolve and support their claims; severity for A3 holds, but P2 is overstated as default-config-reachable (external attacker has public REMOTE_ADDR so forwarded Host is ignored), the 'fork' framing is wrong (upstream rodauth), and fix step #2 does not actually close A3 — only step #1 (repin base_url) does.

Discrepancies:
- P2 default-config applicability overstated: resolution doc says 'P2 is latent in all configs' and register treats it as default-reachable, but an external attacker in default config has a PUBLIC REMOTE_ADDR -> private_ip? false -> only Host header consulted, forwarded headers ignored. Finding 04 line 175 itself concedes the public-client case is safe. P2 requires a private/loopback/SSRF vantage, so it is NOT exploitable in the out-of-the-box single-external-attacker config.
- A3/P2 conflated as 'same underlying weakness' but they have distinct sinks: A3 email links read raw HTTP_HOST (bypasses DetectHost); P2 is the DetectHost->DomainStrategy routing/reflection path. The shared-remediation framing obscures that #2 does not fix A3.

### A4 — confirmed, fix sound_with_caveats
A4 is a confirmed real vulnerability with all citations resolving accurately and severity (High, SSO-gated, not default-reachable) correctly calibrated; the prescribed fix is sound but contingent on the unimplemented #3499 helper and omits the repeat-login identity path, and the 'fork' label on the upstream rubygems gem is a cosmetic meta-error.

Discrepancies:
- Fix depends on unimplemented #3499 helper (resolve_omniauth_email); not yet present in app source, so the resolution is a plan, not verifiable as code.
- Fix omits the account_from_omniauth_identity linking path (gem omniauth.rb:62), which would also bypass a check placed only in account_from_omniauth.

### P1 — partial, fix sound_with_caveats
Citations all resolve and the path-keyed exemption is structurally real, but the assessment overstates it as High by silently ignoring the default SameSite=Lax cookie that blocks the described cross-site POST attack — realistic severity is Medium, default-config unreachable (auth off), and the prescribed fix is sound in intent but reads a never-populated env key, so it must key on credential presence instead.

Discrepancies:
- Material omission inflating severity: neither finding (04/06) nor resolution mentions the session cookie already defaults to SameSite=Lax (boot.rb:83, applied middleware_stack.rb:318). Lax blocks the exact described attack (cross-site form/fetch POST does not carry a Lax cookie), reducing realistic exploitability from High to Medium.
- default_config 'No' is correct but for a reason the docs don't state: when auth is OFF (default), account_creation_allowed? early-returns and 'sessionauth' is never registered (auth_strategies.rb:30-34), so the vuln is unreachable out-of-the-box independent of SameSite.
- Fix sketch reads env['otts.auth_method'] that is never populated and would not exist at middleware time given post-routing auth wrapping — internal mechanism/ordering error in the resolution.

### S1 — confirmed, fix sound
S1 is confirmed: CSP defaults off (config.defaults.yaml:353) and helpers.rb:171 is the sole emitter gated on enabled==true, so a default install (auth off) ships no CSP; citations resolve with only minor line drift, and the fix is sound - the one flaw is the cited live-confirmed evidence file is absent from the repo.

Discrepancies:
- The 'live-confirmed' evidence artifact evidence/headers_output.txt is referenced by the resolution doc, finding 05, exec report (line 136), and risk register (line 16), but no evidence/ directory exists in the assessment folder - the live-confirmation claim is unsupported by any committed file. Code analysis independently confirms the behavior, so the finding still holds.
- Citation range helpers.rb:171-208 ends 4 lines before the actual header-emit at line 212; the gate (171) and policy directives are squarely in-range - minor drift, not a mispoint.

### S2 — confirmed, fix sound_with_caveats
S2 is a confirmed, accurately-cited High default-config weakness (no X-Frame-Options, no frame-ancestors, no HSTS out of the box); the only blemishes are a non-existent evidence file cited as live proof and a fix that understates the HSTS/COOP implementation work beyond config flips.

Discrepancies:
- The 'Confirmed live' empirical claim (X-Frame-Options/HSTS absent on /api/v2/status) cites ../evidence/headers_output.txt, which does not exist; no evidence/ directory is present in the assessment tree (only poc/headers_check.rb). Cited identically in resolution doc, finding 05, and risk-register row S2 — a non-resolving citation for the load-bearing empirical proof.
- head-base.rue:8-9 is off by one line (referrer meta at line 7) — minor drift, right construct present.
- Fix understates HSTS work: a strict_transport default flip alone emits HSTS on plain HTTP since Rack::Protection::StrictTransport adds the header unconditionally; the promised HTTPS guard is unbuilt.

### D1 — confirmed, fix sound
D1 is a confirmed real vulnerability with accurate finding-side citations and a sound, complete fix (bump to >= 2.0.22, permitted by the existing constraint); only cosmetic defects remain — the resolution doc names the wrong transitive chain and mis-describes the lockfile range format.

Discrepancies:
- Resolution doc (D1-oauth2-cve.md:7-8,27,41) states the transitive chain is omniauth_openid_connect → openid_connect → rack-oauth2; that is the wrong consumer (rack-oauth2 is an independent gem). The actual oauth2 consumers are omniauth-oauth2 (1.9.0) and omniauth-google-oauth2 (1.2.2) per Gemfile.lock:290,294 — which the FINDING file (06 §1.1) cites correctly. Finding/fix docs disagree on the chain; finding is right.
- Resolution verification step (D1-oauth2-cve.md:27,41) instructs confirming `Gemfile.lock shows oauth2 (>= 2.0.22)`, but Gemfile.lock records a single resolved version (e.g. 2.0.24), never a range. Cosmetic, not load-bearing.

### C2 — confirmed, fix sound
C2 is accurate and confirmed: every default OTS deployment shares Familia's hardcoded 'FamilialMatters' HKDF salt/BLAKE2b personalization with no app override; all citations resolve in familia-2.11.0 and support the claims; Medium severity is correctly calibrated as bounded defense-in-depth weakening, and the prescribed fix is sound (and safer than the doc assumes, since rbnacl is absent so the history-safe AES-GCM path is the live writer).

Discrepancies:
- Finding-side citations (file 03) use authoring-environment absolute paths /home/user/onetimesecret/... and /home/user/familia/...; all resolve correctly to the worktree and familia-2.11.0 gem — cosmetic, not mispoints.
- base_secret_action.rb:127 (resolution doc) resolves to apps/api/v2/logic/secrets/base_secret_action.rb:127 (@ttl = 30.days max TTL bound) — abbreviated path, correct construct; the '7 day default' part of the prose isn't at that line but the 30-day cap is.

### C3 — confirmed, fix sound_with_caveats
C3 is a real, reachable-by-default Medium: V1 ShowSecret lacks the per-secret passphrase lockout that V2 has, a wrong guess leaves the secret viewable (state→previewed), and V1 routes are mounted unconditionally — citations all resolve with only minor line drift, and the prescribed shared-bucket fix is sound apart from an honestly-flagged V1 LimitExceeded-rendering caveat.

Discrepancies:
- Snippet line labels in resolution doc (raise_concerns@29, process@33) and risk register (show_secret.rb:26-31) are off by ~2 lines from actual (raise_concerns@26, process@30); right constructs present — minor drift, not a mispoint.
- Default-config applicability independently confirmed: V1::Application sets @uri_prefix='/api/v1' (application.rb:63) and auto-registers via base.rb inherited hook (212-216) with no enable flag; routes.txt exposes POST /secret/:key as anonymous. So V1 is routable out-of-the-box.

### P3 — confirmed, fix sound
Accurate, well-cited Medium: V1 limiter is genuinely fail-open and auth-exempt and V2/V3 secret creation plus login have no app-layer throttle in the default (auth-off) config; every finding- and fix-side citation resolves to the right construct and the prescribed reuse-the-feedback-limiter fix is sound and feasible.

Discrepancies:
- Fix doc cites otto gem files via the assessment author's absolute path /home/user/otto/lib/... rather than the standardized otto-2.3.1 gem path; constructs resolve correctly (utils.rb:112-140, request.rb:122-132) so this is a path-format artifact, not a mispoint.
- P3 does not invoke the disputed rodauth/rodauth-omniauth 'fork' framing — its lockout.rb citation is the OTS app config (apps/web/auth/config/features/lockout.rb, max_invalid_logins 5 at line 15), not a gem file, so the fork meta-check does not apply here.

### AZ1 — confirmed, fix sound
AZ1 is accurate and well-cited: RemoveMember genuinely is the lone member-mgmt endpoint bypassing the fail-closed entitlement gate, the fix is sound, severity Medium holds; the only defect is an internal contradiction where the resolution doc marks default-config 'Yes' while the register correctly marks it 'No (orgs)' — not reachable in the auth-OFF default deploy.

Discrepancies:
- Internal contradiction on default-config: resolution doc line 5 says 'Affects default config? Yes', but risk-register.md:23 and finding header say 'No (orgs)'. Register is correct — with auth OFF (default deploy) this authenticated multi-member-org endpoint is unreachable; resolution doc conflates 'feature exists' with 'reachable out-of-box'.
- Sibling invitation endpoints cited under 'logic/members/' actually reside in apps/api/organizations/logic/invitations/. Line numbers and method calls accurate; only directory label drifts.
- Finding correctly self-labels as 'not directly exploitable today' (plain member hits else-deny at remove_member.rb:174-179); defense-in-depth/consistency finding, appropriately Medium, not active priv-esc.

### AZ2 — confirmed, fix sound_with_caveats
AZ2 is a confirmed Medium: get_organization leaks objid/identifier, created_by (owner custid), and contact/billing PII to any member, but the finding mis-attributes the owner-custid leak to owner_id (already stripped by serialize_organization) when it actually rides on created_by, and the prescribed fix targets the wrong sink (safe_dump instead of serialize_organization), introducing id/owner_extid/role regressions.

Discrepancies:
- Finding analyzes the raw safe_dump field list and does not account for serialize_organization (apps/api/organizations/logic/base.rb:61) which is the actual sink for get_organization. The serializer already strips owner_id (base.rb:74) and converts to owner_extid (base.rb:72), so the owner_id-specific leak claim (title/exec line 163/resolution lines 23,32) overstates the actual API exposure.
- BUT the practical 'owner custid leaks to any member' claim still holds via the co-cited created_by (safe_dump:27): created_by = creator's custid (organization.rb:68) and the standardize_owner_id chore keeps created_by == owner_id (organization.rb:434, chore lines 10-11). created_by is NOT stripped by the serializer. So owner custid does leak — via created_by, not owner_id.
- objid still leaks through get_organization despite the serializer: base.rb:66 explicitly aliases record[:id] = record[:objid], and safe_dump includes objid — confirming the AZ5-linkage concern.

### AZ3 — partial, fix sound_with_caveats
The mass-assignment mechanism is genuinely present and the familia citations are exact, but it is latent (no caller forwards user-controlled params, so not reachable in default config); the 'sole caller' claim and the planid:87 citation are inaccurate, and the prescribed allowlist would regress two callers that pass `is_default: true` through the splat.

Discrepancies:
- 'Sole current caller' framing is false: there are 3+ production callers of Organization.create! (create_organization.rb:99, plans.rb:335, welcome.rb:383, create_default_workspace.rb:80) plus CLI/try fixtures. The NEEDS-VALIDATION question still resolves negative — every caller passes only literals/fixed args, none forwards a raw params hash — so the 'latent, not live' conclusion holds, but the supporting claim is inaccurate.
- planid cited as plain field at organization.rb:87 is a mispoint: 87 is init's `@planid ||=` default; the field declaration is in with_organization_billing.rb:34. planid is a billing-concern field, not a core :65-72 plain field.
- Fix doc internally contradicts reality: step 2 asserts the caller 'lands on the empty/allowlisted path unchanged,' but two callers pass is_default: true through the splat — the proposed allowlist would raise on them (regression).

### AZ4 — partial, fix sound_with_caveats
All AZ4 citations resolve and support the claims exactly; the model-layer weakness is real but latent (no reachable path lets a non-owner set owner today, so default-config exploitability is No — contradicting the resolution doc's 'Yes' header), and the step-1 allowlist fix is sound while transfer_ownership! remains an explicitly-deferred sketch.

Discrepancies:
- Internal contradiction on default-config: resolution doc header says 'Affects default config? Yes' (line 5) but the risk register row says 'No (orgs)'. Register is the more defensible reading for reachability (out-of-box, no second caller passes 'owner'); the resolution header overstates.
- Resolution understates the existing defense: the live endpoint blocks owner THREE ways (VALID_ROLES allowlist :131, target owner? guard :141, new_role=='owner' :160), not just the single :159-167 check the doc emphasizes — strengthens 'not currently reachable'.
- grep confirms doc claims (line 43, 139): zero transfer_ownership references; only change_role! caller outside specs is update_member_role.rb:67, gated by validate_role_change! at :58. NEEDS-VALIDATION resolves to: no reachable path lets a non-owner set owner today — latent/defense-in-depth, not a live vuln.

### AZ5 — confirmed, fix sound
AZ5 is a real but low-practical-impact defense-in-depth weakness; all finding- and fix-side citations resolve and support their claims (no version drift in familia 2.11.0), default-config is correctly marked not-reachable, and the prescribed keyed-HMAC fix is sound with the persisted-extid migration path empirically confirmed in the gem.

Discrepancies:
- Internal inconsistency on default-config: resolution doc line 5 says 'Affects default config? Yes' while register line 27 + exec say 'No (orgs)'. They answer different questions (weak derivation present everywhere vs. not exploitable out-of-box). For reachable_default_config the register's 'No' is correct: default deploy is auth OFF / no orgs, and exploitation additionally requires an objid leak (AZ2) plus cross-org objid knowledge.
- Severity Medium is generously calibrated for a defense-in-depth gap: it is NEEDS-VALIDATION with no confirmed production sink and is non-exploitable until AZ2 leaks an objid AND an attacker obtains a *target* org's objid out-of-band. Defensible as Medium given the AZ2 compounding, but borderline Low; not a clear miscalibration.

### A5 — confirmed, fix sound
A5 is a real, correctly-scoped Medium: recovery codes stored verbatim in upstream rodauth-2.42.0 with no built-in hashing toggle and OTS overrides only the generator; finding citations accurate (minor line drift), the in-doc 'no toggle' correction is verified true, and the HMAC-override fix is sound; only meta-issue is the inaccurate 'fork' labeling of upstream gem files.

Discrepancies:
- base.rb line citations stale: compute_hmac cited :279 (actual 251), timing_safe_eql? cited :726 (actual 695) in 2.42.0; line drift, constructs present and support the fix.
- OTS-override-absence confirmed both sides: mfa.rb overrides ONLY new_recovery_code (L74-76); no storage/compare override in apps/web/auth or config. A5's 'OTS didn't override storage' claim holds.

### A6 — partial, fix sound_with_caveats
A6 is real in mechanism and accurately cited (Medium, not default-reachable, correctly NEEDS-VALIDATION on the A3/P2 host-trust precondition); fix is sound with the honest RP-ID-invalidation caveat, but the 'fork rodauth' label is wrong (upstream gem) and the upstream default is itself request-derived, tempering the framing.

Discrepancies:
- Nuance the finding omits: upstream rodauth default webauthn_origin = base_url (webauthn.rb:336-338), and base_url itself defaults to request.base_url unless pinned. So OTS's request.host override is request-derived in the same spirit as the upstream default — the weakness is 'no pinned base_url/origin', not a uniquely-OTS regression. Doesn't change the fix but tempers the framing.
- 'WebAuthn conditionally enabled (webauthn.rb:9-11)' is imprecise: line 9 enables :webauthn/:webauthn_login unconditionally within the block; the actual gate is config.rb:122 (if webauthn_enabled?). Conditional gating is real, citation just points at the wrong line.

### A7 — confirmed, fix sound_with_caveats
A7 is confirmed and correctly scoped: reset enumeration (distinct 401/403/200) and no max password length are both real upstream-default gaps OTS left unhardened; severity Medium and default-config=No are correct; fix is sound (A7b one-line, A7a mirrors email_auth) with the timing-oracle caveat the doc itself flags — only blemishes are wrong base.rb line numbers and the inaccurate 'fork' label on plain-upstream rodauth.

Discrepancies:
- base.rb line citations in resolution doc are mispointed: 401-status cited at :59 (actual :46), 403 at :80 (actual :67), only_json? at :46 (actual :437 — and :46 is the 401 line). Values correct, line numbers wrong; likely version-drift artifact, does not break the claim.
- Finding-side doc (01-authn-session.md:159-160,173) cites the same constructs with correct ranges and is verified by grep ('overrides email_auth but NOT reset_password' confirmed: email_auth.rb:27 has the override, no reset override exists).

### A8 — confirmed, fix sound
A8 is a real, accurately-cited Medium: a 1-day per-account lockout (rodauth default, unoverridden by OTS) is a trivially weaponizable targeted DoS, not reachable in the default auth-off config; the fix correctly retargets the real interval knob, and the only blemishes are the upstream-mislabeled-as-fork framing and a ~9-line before_login_attempt drift.

Discrepancies:
- before_login_attempt cited as :263-268 but is at :254-258 in 2.42.0 (~9-line drift, likely version drift from the authored-against version); right construct, quoted block matches exactly — minor drift, not a mispoint.

### D2 — confirmed, fix sound
D2 is a confirmed real prod-tree JS CVE with all citations resolving exactly; severity (Medium-in-practice given the browser-only axios usage) and default-config "Yes" are both correctly calibrated, and the override fix is sound and complete across both transitive paths.

Discrepancies:
- Scanner rates this High (CVSS 8.7); the assessment downgrades to Medium-in-practice on the mitigation that axios's browser XHR/fetch adapter uses native FormData, not the Node form-data helper. This reasoning is technically sound and the latent-reactivation caveat (future SSR/Node multipart use) is acknowledged — not an overclaim.

### D3 — confirmed, fix sound
D3 is a real, default-reachable Medium info-disclosure: production source maps are emitted unconditionally and served at /dist by the default-on static middleware, fly statics, and Caddy proxy; every citation resolves and the 'hidden'+CI-strip fix is sound.

### D4 — confirmed, fix sound
D4 is fully confirmed and accurately cited — root-running, unpinned, recommends-laden internet-facing Caddy proxy in the full stack — with a sound fix; the only caveat is that it lives in the full compose topology, not the bare auth-OFF default.

Discrepancies:
- default-config nuance: D4 is reachable only in the FULL compose stack (docker-compose.full.yml builds+runs this image on 80/443; simple compose has no proxy). It is NOT exploitable in the stated out-of-the-box default (auth/SSO/diagnostics OFF) because that default topology is orthogonal — the simple stack ships no Caddy. The finding and register honestly scope it as '(Caddy variant)' rather than claiming the bare default; reachable_default_config=false against the task's literal default definition.
- Finding file 06 cites apt as 'lines 90-96' and COPY as 'line ~112'; actual are 91-97 and 114 — 1-2 line drift, right construct. Resolution doc cites them exactly (91-97, 114). No mispoint.

### D5 — confirmed, fix sound
D5 is fully confirmed — every citation resolves and supports the claim, the unauthenticated/host-exposed datastore and guest:guest RabbitMQ are real and reachable in the default compose config, severity Medium is defensible, and the prescribed fail-closed fix is sound and complete.

### S3 — confirmed, fix sound_with_caveats
S3 is a real, accurately-cited Medium: revealed plaintext lingers in the Pinia store (plus a duplicate payload ref) with no teardown clear, and the prescribed onBeforeUnmount/route-guard fix is sound (honestly scoped as lifetime-minimization, not zeroization); the only defect is an internal contradiction on default-config applicability (resolution doc says No, register says Yes — Yes is correct).

Discrepancies:
- Internal contradiction on default-config applicability: resolution doc line 5 says 'Affects default config? No (behavioral; independent of any config flag)', but risk-register.md:36 marks Default?=Yes. The vuln IS reachable in default config (no auth/SSO/diagnostics needed — any recipient reveal populates the store), so the register's 'Yes' is correct and the resolution doc's 'No' is the error.
- Minor path looseness: resolution line 20 prose says the only onUnmounted is in 'branded/BaseSecretDisplay.vue' and primary-files line 11 cites 'shared/components/base/BaseShowSecret.vue' correctly but 'branded/SecretDisplayCase.vue' abbreviated; the branded components actually live under apps/secret/components/branded/, not shared/components/branded/. Abbreviated forms resolve; no mispoint.

### C4 — confirmed, fix sound
C4 is confirmed with all citations resolving accurately; C4a (non-atomic check-then-record) is a real default-reachable bounded over-shoot and the reserve-before-verify+refund Lua fix is sound, while C4b (test Argon2 cost) is config-dependent not default — a nuance the resolution doc honors but the register's 'Default? Yes' one-liner over-generalizes.

Discrepancies:
- Default-config nuance: C4a (non-atomic gate) IS default-reachable (reveal is a guest route enabled by default, auth-off). C4b (test Argon2 cost) is NOT default-reachable — it requires a misconfigured RACK_ENV=test in production; boot.rb:111 defaults to production. The resolution doc honestly labels this 'Partially' default, but the risk-register/exec one-line 'Default? Yes' over-generalizes by attributing default-applicability to the whole C4 including C4b.
- Severity Medium is defensible: C4a is a bounded (next-window-locked) over-shoot, not an unbounded bypass — the doc states this accurately and does not overclaim.

### C5 — confirmed, fix sound
C5 is a confirmed, default-config-reachable Low-severity unbounded-payload DoS; all ~10 app/lib citations resolve and support the claim, the fix is root-cause-correct and complete in scope, with one fix-side filename slip (gitignored etc/config.yaml vs the defaults file) that is minor drift, not a mispoint.

Discrepancies:
- Fix-side: config knob cited at etc/config.yaml:198-220, but etc/config.yaml is gitignored (user-override that deep-merges over etc/defaults/config.defaults.yaml); the secret_options block at those exact lines lives in the defaults file. Correct intent (deployers add overrides in etc/config.yaml), borrowed line numbers — minor drift.
- Fix-side: manager.rb:17-23 is an unqualified abbreviation; resolves to familia gem (familia-2.11.0/lib/familia/encryption/manager.rb), not an app file. Claim (plaintext copied in memory) holds.
- Finding-side (03 file) uses /home/user/onetimesecret/... absolute path prefixes — portable-path artifact from authoring machine; resolves fine against the worktree, not a resolution failure.

### C6 — confirmed, fix sound
C6 is accurately characterized and correctly rated Low/informational: the v1 unsalted-SHA256 key exists by default as a read-only decrypt fallback (never used for writes, no downgrade path), every load-bearing citation resolves, and the retirement fix is sound with an explicit data-loss gate and fail-closed removal.

Discrepancies:
- Minor citation drift on base_secret_action.rb:113,127 (TTL bounds) — actual values at L45/143/151; peripheral to the core claim, not a mispoint.
- Finding-side file (03-redis-familia-crypto.md) uses /home/user/... absolute paths from the authoring environment, but the cited line (configure_familia.rb:65) is exact; path prefix is cosmetic.

### AZ6 — confirmed, fix sound
AZ6 is a real, default-reachable Low-severity internal-id leak with pixel-accurate citations and a sound, complete fix; only nit is the headline naming owner_id while custid (which can be a legacy email) leaks too.

Discrepancies:
- Exec report (00:194) and risk-register (line 40) title the finding 'exposes creator owner_id' only; the actual leak and the fix cover BOTH custid and owner_id (safe_dump_fields.rb:56-57). Finding body (02 F6) and resolution doc correctly cover both. Minor scope understatement in the headline, not the body.
- custid is a real field via deprecated_fields.rb:25; per migration_fields.rb:13 custid in v2 data can be a legacy EMAIL address (or 'anon'), not just an opaque id. The assessment frames custid uniformly as 'internal customer id' and does not note it can be an email — a slight under-characterization (an email leak is arguably worse), but possession-gating keeps severity Low.

### AZ7 — confirmed, fix sound_with_caveats
AZ7 is fully confirmed with all finding-side and fix-side citations resolving exactly; severity Low is upheld and the fix is sound except its inviter-attribution snippet references a non-existent Customer display_name field (the doc already hedges to 'omit'), and the register's 'No' default-config flag mildly contradicts the resolution doc's 'Yes'.

Discrepancies:
- Register row marks AZ7 'No (invites)' for default-config, but the resolution doc itself says 'Affects default config? Yes (the noauth GET /api/invite/:token endpoint)'. The endpoint is reachable without auth (apps/api/invite/auth_strategies.rb:12 noauth); exploitation requires a valid invite token, so it is not out-of-the-box reachable absent an issued invite. Minor internal inconsistency between resolution doc and register, but both defensibly Low.
- Fix snippet references Customer#display_name / safe_dump :display_name which does not exist; implementer following the snippet literally gets nil. Hedged but should be corrected to 'omit'.

### AZ8 — partial, fix incomplete
Finding citations all accurate and the model-layer mass-assignment weakness is real but unreachable today (no params-forwarding sink), so Low/NEEDS-VALIDATION is correctly calibrated; the prescribed fix is incomplete because its forbidden-fields raise would regress two of three callers (create_customer.rb, sync_session.rb) that pass role:/verified: directly into create!, which the doc overlooked.

Discrepancies:
- Fix-side blind spot: resolution doc verified only create_account.rb's caller pattern. create_customer.rb:62-68 and sync_session.rb:175-178 pass role:/verified: directly as create! kwargs, so the prescribed CREATE_FORBIDDEN_ATTRS raise would regress them — contradicting step-2's 'callers unaffected' claim.
- NEEDS-VALIDATION resolved: no production path forwards a raw params hash or ** splat into Customer.create! (grep confirms only keyword literals); not exploitable in default config. The 'safe today' framing is correct.

### AZ9 — confirmed, fix sound
AZ9 is a real, accurately-cited gap (anonymous email-amplifying incoming endpoints with no in-app rate limit and no middleware limiter in this codebase); severity Low and default-config "No (incoming, opt-in)" are correct, and the prescribed limiter fix is sound and complete across both paths.

Discrepancies:
- NEEDS-VALIDATION resolved: no in-app or Rack/middleware rate limiter wraps the incoming routes anywhere in this codebase (grep of lib/onetime, config, apps/api/incoming clean). Whether a production reverse-proxy/WAF throttles them is deployment-specific and unverifiable from source; the finding correctly states this and the in-app fix is the right defense-in-depth regardless.

### P4 — confirmed, fix unsound
The V1 timing asymmetry is genuinely present and correctly rated Low and not-reachable-in-default-config, but the prescribed fix is unsound — Customer.dummy has no apitoken so apitoken? short-circuits, and the doc's 'expensive BCrypt' premise is wrong since V1 uses cheap secure_compare.

Discrepancies:
- Fix is unsound: Customer.dummy (customer.rb:331-340) never sets apitoken; apitoken?:263 empty-guard short-circuits before secure_compare, so the 'mirror V2/V3 dummy' fix yields no timing parity.
- Finding+fix mischaracterize the cost: V1 apitoken? uses Rack::Utils.secure_compare (customer.rb:265), not BCrypt; the 'expensive comparison'/'~280ms BCrypt' framing (resolution lines 22-28,52, doc step 1/3) is inaccurate and overstates the timing signal.
- Finding premise 'V2/V3 do NOT have this problem' (04-api-otto.md:162) is weakened: basic_auth_strategy.rb:57 calls apitoken? on the same dummy that lacks an apitoken, so the cited constant-time reference does not actually exercise the dummy's Argon2 hash on the apitoken path either.

### P5 — confirmed, fix sound
P5 is a real, accurately-cited Low-severity log-injection of the Basic-Auth username via OT.ld, correctly scoped as not-default-config (debug + auth must both be on, and the sink is short-circuited when auth is disabled); the fix is sound with one imprecision (base.rb:80-81 logs IP, not custid).

Discrepancies:
- Resolution doc lists base.rb:80-81 (anonymous path) as a custid log-injection site, but that branch logs only client_ipaddress and custid is nil there — overscoped, though hedged with 'for any untrusted field'.
- helpers.rb:113 cited as a 'similar site' logs custid=cust&.custid (authenticated value) and :86 logs 'obscured', not raw attacker Basic-Auth input — weaker analogues than base.rb:67, listed as defense-in-depth not equivalent sinks.
- Not flagged in docs but reinforces 'No (auth)': base.rb:65 returns disabled_response BEFORE the :67 log line when session_auth_enforced? is false, so the sink is unreachable when auth is OFF.

### S4 — confirmed, fix sound
S4 is accurate and well-calibrated: every citation resolves exactly, the v-html sink is real but operator-controlled and DOMPurify-mitigated (Low/defense-in-depth upheld), the fix is sound; only flaw is an internal Yes/No default-config inconsistency between register and resolution and an over-claim that the DOMPurify hook can be call-scoped.

Discrepancies:
- Internal contradiction on default-config: risk-register.md:46 marks 'Affects default config? Yes' but resolution doc header (line 5) says 'No'. Truth is nuanced: the sink ships in default config (not auth-gated) but renders nothing until an operator sets global_banner (bootstrap.ts:580 defaults null), so it is not exploitable out-of-the-box. The 'No' framing is more accurate for exploitability.
- Resolution step 2 claims the afterSanitizeAttributes hook can be 'kept scoped to this component's sanitize call' — DOMPurify hooks are global to the singleton; not actually scopable per-call without a separate DOMPurify instance.

### S5 — partial, fix sound
All citations resolve and support their claims; S5 is correctly classified as a Low NEEDS-VALIDATION CSP-compatibility concern (not a real injection risk — the script src is a fixed vendored constant), not reachable in default config (CSP off, requires authenticated custom-domain admin flow with dns_widget flag), and the prescribed fix is sound.

Discrepancies:
- The finding-side file 05 #6 header says 'CONFIRMED behavior' while marking it NEEDS-VALIDATION; the two are reconciled correctly — the no-nonce injection is confirmed, but whether it actually breaks under CSP is the open (and likely negative) question. Not a discrepancy.
- Not a script-injection risk: script.src is a fixed compile-time vendored constant (dnsWidgetJs), no attacker-controlled input. This is a CSP-compatibility/future-proofing concern only, as the docs correctly state.

### OBS1 — confirmed, fix sound
OBS1 is accurate, all citations resolve exactly, correctly self-classified as Info/non-default-config (double-gated to dev + DEBUG_SESSION), and the redaction+boot-guard fix is sound.
---
_38 findings re-verified; verify→adversarial-recheck (76 agents) + C1 runtime reproduction. 0 overturns._
