# OneTimeSecret — Security Assessment (Findings Report)

**Engagement:** Authorized deep security review of the OneTimeSecret web application and its
supporting libraries (source + local runtime).
**Date:** 2026-06-22  **Branch under review:** `claude/vigilant-goldberg-97ijfl` (all 5 repos)
**Assessor role:** Application Security Engineer (defensive, synthetic data only).

Repositories in scope (all reviewed):
`onetimesecret/onetimesecret` (app), `delano/otto` (web framework), `delano/familia` (Redis ORM),
`onetimesecret/rodauth` (auth fork), `onetimesecret/rodauth-omniauth` (SSO fork).

> **Detailed evidence** for every item lives in the per-area files in this directory
> (`01`–`06`). This document is the executive synthesis + risk register + reproduction summary.
> The risk register is also available standalone at `../risk-register.md`.

---

## 1. Executive summary

OneTimeSecret is a **mature, security-conscious codebase**. Cryptographic fundamentals are strong:
secret share identifiers are 256-bit CSPRNG values with an HMAC authenticity tag (not guessable),
secrets are encrypted at rest with authenticated encryption (AES-256-GCM / XChaCha20-Poly1305),
fresh per-message nonces, HKDF key derivation, and ciphertext is cryptographically bound to its
record. Passphrases use Argon2id. There is **no insecure default secret** — the app fails closed
if `SECRET` is unset. The authorization model is a coherent entitlement system with a verified-email
-gated admin ("colonel") role, and the otto framework's routing, dynamic-dispatch allowlisting, and
trusted-proxy/client-IP handling are well designed.

The material risk concentrates in a few areas:

1. **The core "one-time" guarantee is not concurrency-safe (HIGH, PoC-confirmed).** The reveal/burn
   flow is a non-atomic check-then-destroy. Under real parallelism (production runs multiple Puma
   worker processes) the *same* secret can be revealed to multiple parties. **Demonstrated live:
   12/12 independent processes obtained the plaintext of a single one-time secret.**
2. **SSO/OIDC integration has an account-takeover path (CRITICAL) and an MFA bypass (HIGH)** — gated
   on SSO being enabled, but serious where it is.
3. **Secure-by-default gaps**: CSP, X-Frame-Options/clickjacking protection, and HSTS are **off by
   default** (HIGH, live-confirmed); cookie-authenticated `/api/*` mutations are exempted from CSRF
   token checks (HIGH).
4. **One genuinely exploitable dependency CVE**: `oauth2` 2.0.18 bearer-token leak (HIGH), reachable
   through the SSO login path.
5. **Host-header trust gap** feeds password-reset / magic-link / verification email links (HIGH).

Most CRITICAL/HIGH auth items are **gated on authentication or SSO being enabled** (both off in the
default config). For the **default anonymous-sharing deployment**, the highest-impact issues are the
one-time race (#1), the missing CSP/clickjacking/HSTS defaults (#3), and — if any logged-in features
are used — CSRF (#3).

**Tally:** 1 Critical, 8 High, ~16 Medium, ~11 Low/Info. Full list in §3.

---

## 2. Methodology, environment & coverage

- **Source review** of all 5 repos (read-only), plus **dynamic analysis**: built Ruby 3.4.9,
  `bundle install`, booted the real application stack in-process against a local Redis, and drove the
  genuine otto→logic→model→Redis paths via `Rack::MockRequest` and multi-process workers.
- **Parallelized** across six focused analysis workers (auth/session, authz/IDOR, redis/familia/crypto,
  REST API/otto, SPA, supply chain) whose detailed outputs are files `01`–`06`. The headline race
  finding was independently reached by both the lead assessor and the crypto worker, then confirmed
  with a live PoC.
- **Tooling & reproduction:** see `../notes/tooling.md` and `../poc/`. Dependency findings were
  confirmed with `bundler-audit` (ruby-advisory-db) and `pnpm audit` against live advisory DBs.

**Focus-area coverage (Definition of Done):**

| # | Focus area | Covered in | Key outcome |
|---|------------|-----------|-------------|
| 1 | Auth & session mgmt | 01 | CRITICAL SSO takeover; HIGH MFA bypass/host-header; session store sound |
| 2 | Authorization / IDOR / tenant | 02 | No Critical/High; Medium defense-in-depth gaps |
| 3 | Redis-specific risks | 03 | One-time race (HIGH); Lua safe; key naming sound |
| 4 | REST API security | 04 | HIGH CSRF-exempt prefix; rate-limit gaps; otto solid |
| 5 | SPA security | 05 | HIGH CSP/clickjacking off-by-default; secret display safe |
| 6 | Supply chain | 06 | HIGH oauth2 CVE; container/redis hardening |
| 7 | Runtime & deployment | 06 | unauth Redis + host-exposed compose; source maps; secrets fail-closed |
| 8 | Business logic | 01/02/03 | one-time race; enumeration items; incoming-email abuse |
| 9 | Cryptography | 03 | Strong (AEAD, CSPRNG, Argon2id, HKDF, AAD); salt-default caveat |
| 10 | Observability | 01/06 | session debug gated; Sentry scrubbing present; logging mostly safe |

---

## 3. Consolidated findings (risk-ranked)

Severity reflects impact **when the relevant feature is enabled**. "Applicability" notes the
precondition. IDs map to the per-area files.

### CRITICAL

- **[A1] SSO email-match account takeover.** `account_from_omniauth` links an SSO identity to any
  existing local account purely by normalized email, with `omniauth_verify_account? true` and **no
  `email_verified` claim check**. An attacker who can authenticate at a configured IdP (or tenant SSO)
  as the victim's email — e.g. an OIDC provider that does not verify email ownership — takes over the
  victim's existing account.
  Evidence: `apps/web/auth/config/hooks/omniauth.rb:27-30`, `config/features/omniauth.rb:38-40`;
  fork `rodauth-omniauth/lib/rodauth/features/omniauth.rb:58-99,151-153`. *(Detail: 01)*
  **Applicability:** SSO/OmniAuth enabled with a provider/tenant that doesn't guarantee verified email.

### HIGH

- **[C1] TOCTOU race defeats the one-time guarantee — PoC-CONFIRMED.** Reveal/burn does a non-atomic
  check-then-destroy: in-memory `state` is checked, the value is decrypted, then `destroy!` runs
  unconditionally (no `WATCH`/Lua/`GETDEL`/lock). Two+ concurrent requests for the same secret each
  pass the gate, decrypt, and destroy — all receive the plaintext.
  Evidence: `lib/onetime/models/secret/features/secret_state_management.rb:60-90`;
  `apps/api/v2/logic/secrets/reveal_secret.rb:64,95,189`; v1 `apps/api/v1/logic/secrets/show_secret.rb:27,50,71`;
  `familia/lib/familia/horreum/persistence.rb:558` + `database_commands.rb:252,242`.
  **Live PoC:** `../poc/race_reveal_model.rb` (deterministic 10/10) and multi-process workers
  (`../poc/_reveal_worker.rb`) → **12/12 independent processes obtained the same secret's plaintext**
  (`../evidence/race_poc_output.txt`). *(Detail: 03 F1)*
  **Applicability:** default config (anonymous sharing); impact = single-use/tamper-evidence broken.

- **[A2] SSO bypasses MFA unconditionally.** `via_omniauth: true` short-circuits the MFA requirement
  before any policy override — a TOTP/WebAuthn-protected account logs in via SSO with no second factor.
  Evidence: `apps/web/auth/config/hooks/login.rb:128-133`, `operations/detect_mfa_requirement.rb:151-156`. *(01)*
  **Applicability:** SSO + MFA both in use.

- **[A3] Host-header poisoning of reset / magic-link / verification emails.** Links are built from
  `request.base_url`; OTS never overrides Rodauth `base_url`, and `DetectHost`/`DomainStrategy` don't
  reject untrusted Host values — so single-use tokens can be delivered to an attacker-chosen domain.
  Evidence: `apps/web/auth/config/email/reset_password.rb:14-15`; `lib/middleware/detect_host.rb:156-194`;
  `lib/onetime/middleware/domain_strategy.rb:104-149`. *(01, 04 F3)*
  **Applicability:** auth (password reset / email auth) enabled.

- **[A4] SSO domain allowlist enforced only on account-creation, not on the linking path.**
  `apps/web/auth/config/hooks/omniauth.rb:133-180` vs fork `omniauth.rb:79-87`. Compounds A1. *(01)*

- **[P1] CSRF protection bypassed for cookie-authenticated API mutations.** The entire `/api/` prefix
  is blanket-exempted from token CSRF, yet many `/api/*` POST/PATCH endpoints accept `auth=sessionauth`
  (cookie) — account deletion, password/API-token change, secret creation. The only fallback
  (`HttpOrigin`) is off by default.
  Evidence: `lib/onetime/middleware/security.rb:142`. *(04 #2)*
  **Applicability:** any logged-in (cookie) session using API-backed actions.

- **[S1] CSP disabled by default.** `CSP_ENABLED` defaults false; the policy is only emitted when
  enabled (the policy itself, when on, is strong: nonce-based, no `unsafe-inline`).
  Evidence (live-confirmed, header ABSENT on `/api/v2/status`, `../evidence/headers_output.txt`):
  `etc/defaults/config.defaults.yaml:351-353`; `apps/api/v1/controllers/helpers.rb:171-208`. *(05)*

- **[S2] Clickjacking / HSTS / security headers off by default.** `frame_options`, `strict_transport`,
  `http_origin`, `xss_header` all default false; with CSP also off, a default install ships **neither**
  X-Frame-Options nor `frame-ancestors` → framable/clickjackable, and no HSTS.
  Evidence (live-confirmed ABSENT): `etc/defaults/config.defaults.yaml:314-338`;
  `lib/onetime/middleware/security.rb:76`. *(05, 04 #1)*

- **[D1] `oauth2` 2.0.18 — bearer-token leak (GHSA-pp92-crg2-gfv9).** A protocol-relative redirect can
  leak the `Authorization` header to an attacker host; reachable via the OmniAuth/OIDC login path.
  Fix: bump to `>= 2.0.22` (allowed by the existing constraint). Evidence: `Gemfile.lock:265`. *(06 #1)*
  **Applicability:** SSO/OIDC enabled.

### MEDIUM (defense-in-depth / feature-gated)

- **[C2]** Encryption HKDF salt & BLAKE2b personalization left at the shared library default
  `'FamilialMatters'` — no per-deployment domain separation (bounded: master key still
  deployment-unique). `lib/onetime/initializers/configure_familia.rb:57-72`; `familia/lib/familia/settings.rb:15-16`. *(03 F2)*
- **[C3]** V1 reveal path has **no passphrase rate limiting** (V2 has it) → online passphrase
  brute-force if V1 is routable. `apps/api/v1/logic/secrets/show_secret.rb:26-31`. *(03 F3)*
- **[P2]** `Rack::DetectHost` trusts forwarded Host from any private/loopback peer (its own `private_ip?`),
  not otto 2.3.1 trusted-proxy config → host-header injection from internal/SSRF vantage. `lib/middleware/detect_host.rb:156-165`. *(04 #3)*
- **[P3]** Rate-limiting gaps: no app-layer limiting on auth/login or V2/V3 secret creation; V1 limiter
  is fail-open and exempts authenticated users. `apps/api/v1/controllers/base.rb:145-171`. *(04 #4)*
- **[AZ1]** `RemoveMember` is the only member-mgmt endpoint not using `require_entitlement_in!('manage_members')`
  (relies on raw role-string checks). `apps/api/organizations/logic/members/remove_member.rb:39-58`. *(02 F1)*
- **[AZ2]** Organization `safe_dump` leaks internal `objid`/owner custid/billing+contact emails to any
  active member. `lib/onetime/models/organization/features/safe_dump_fields.rb:17-29`. *(02 F2)*
- **[AZ3]** `Organization.create!` open `**` splat → `planid`/`is_default`/Stripe/`complimentary`
  mass-assignable if any caller forwards user params (safe today; sole caller passes fixed args). *(02 F3, NEEDS-VALIDATION)*
- **[AZ4]** `change_role!` rejects `colonel` but not `owner`; owner-escalation guard lives only in one
  endpoint validator, not the model. `lib/onetime/models/organization_membership.rb:258-274`. *(02 F4, NEEDS-VALIDATION)*
- **[AZ5]** Organization external id uses plain SHA-256 (no keyed HMAC), compounded by AZ2 leaking objid.
  `lib/onetime/models/organization.rb:46`. *(02 F5, NEEDS-VALIDATION)*
- **[A5]** Recovery codes stored in plaintext. `rodauth/lib/rodauth/features/recovery_codes.rb`. *(01)*
- **[A6]** WebAuthn RP-ID/origin derived from `request.host` (ties to host-header trust). `features/webauthn.rb:14-22`. *(01)*
- **[A7]** Password-reset enumeration (distinct 401/403/200); no max password length → Argon2 CPU DoS.
  `features/account_management.rb:104`. *(01)*
- **[A8]** 1-day per-account lockout enables targeted lockout DoS. `features/lockout.rb:15`. *(01)*
- **[D2]** `form-data` 4.0.5 via `axios` (GHSA-hmw2-7cc7-3qxx) — only prod-tree JS CVE; mitigated
  (browser bundle doesn't use the Node helper). Bump axios / override `>= 4.0.6`. `pnpm-lock.yaml:3129`. *(06 #2)*
- **[D3]** Production source maps emitted (`sourcemap: true`) and copied into the image / served at
  `/dist`; use `'hidden'` or strip. `vite.config.ts:283`. *(06 #3, 05)*
- **[D4]** Internet-facing Caddy proxy image runs as **root**, base not digest-pinned, apt without
  `--no-install-recommends`. `docker/variants/caddy.dockerfile:85`. *(06 #4)*
- **[D5]** `docker-compose.simple.yml` runs Valkey `--bind 0.0.0.0` with **no `requirepass`/ACL** and
  **publishes 6379 to the host**; full stack defaults RabbitMQ to `guest:guest`.
  `docker/compose/docker-compose.simple.yml:57-69`, `docker-compose.full.yml:129-130`. *(06 #5)*
- **[S3]** Revealed plaintext not cleared from SPA memory (`clear()`/`$reset()` exist but unused on the
  reveal flow). `src/shared/stores/secretStore.ts:203-216`. *(05)*
- **[C4]** Passphrase rate-limit gate-read and failure-record are separate round-trips → bounded
  >5-attempt overshoot under concurrency; test Argon2 cost selected by `RACK_ENV=test`. *(03 F4)*

### LOW / INFO

- **[C5]** No app-level cap on secret payload size (Redis memory DoS). `apps/api/v2/logic/secrets/conceal_secret.rb`. *(03 F5)*
- **[C6/D6]** Legacy v1 encryption key = unsalted `Base64(SHA256(secret))` (read-compat only; v2=HKDF). `configure_familia.rb:65`. *(03 F6, 06)*
- **[AZ6]** Receipt `safe_dump` exposes creator `owner_id` via anonymous receipt/burn endpoints. *(02 F6)*
- **[AZ7]** `show_invite` (noauth) discloses inviter email + an account-exists oracle. `apps/api/invite/logic/base.rb:51-64`. *(02 F7)*
- **[AZ8]** `Customer.create!` has no allowlist (`role`/`verified` mass-assignable at model layer; safe
  because all signup paths hardcode `'customer'`). *(02 F8)*
- **[AZ9]** No in-logic rate limit on anonymous incoming `/secret` (each emails a recipient). *(02 F9)*
- **[P4]** V1 Basic-Auth username enumeration via timing (no dummy-hash, unlike V2/V3). `apps/api/v1/controllers/base.rb:68-71`. *(04 #5)*
- **[P5]** Log injection of attacker-controlled Basic-Auth username. `apps/api/v1/controllers/base.rb:67`. *(04 #6)*
- **[S4]** `v-html` in `GlobalBroadcast.vue` (DOMPurify-sanitized to `<a>` only; operator-set content). *(05)*
- **[S5]** DNS widget injects a same-origin script without a nonce (would break under strict CSP). *(05)*
- **[OBS1]** `SessionDebugger` can dump full response headers incl. `Set-Cookie` when `DEBUG_SESSION` set (gated/off by default). `lib/middleware/session_debugger.rb:102`. *(06)*

---

## 4. Strong controls verified (no action required)

- **Token unpredictability:** secret/receipt ids = 256-bit `SecureRandom` + 64-bit HMAC tag; HMAC
  secret has no committed default (fails closed). `familia/lib/familia/{secure_identifier,verifiable_identifier}.rb`.
- **Encryption at rest:** AES-256-GCM / XChaCha20-Poly1305 AEAD, fresh CSPRNG nonce per message,
  HKDF/BLAKE2b derivation, **AAD + key context bound to `Class:field:identifier`** (ciphertext can't be
  moved between records). `familia/lib/familia/features/encrypted_fields/encrypted_field_type.rb:183-220`.
- **Passphrases:** Argon2id with library constant-time verify; bcrypt only for legacy reads.
- **No insecure default secret** — app fails closed without `SECRET`; secrets are `SecureRandom.hex(64)` + HKDF.
- **Lua/Redis:** all scripts use bound `KEYS`/`ARGV` (no injection); identifiers pass a strict
  `[^a-zA-Z0-9_-]` allowlist before becoming keys.
- **Session store:** AES-256-GCM + HMAC over Redis, HKDF subkeys, constant-time HMAC compare, session
  id regenerated on login (fixation mitigated), `awaiting_mfa` not treated as authenticated, TOTP replay prevented.
- **otto framework:** trusted-proxy/client-IP resolution well-designed; dynamic `send` dispatch
  allowlisted via `ConstantResolver`; static-file path traversal blocked; **no CORS shipped**; generic
  prod errors with correlation IDs.
- **Authorization core:** entitlement-based; colonel (admin) is a server-side, verified-email-gated role
  enforced at the edge and in all logic actions; no config auto-promotion; no production raw-params sinks.
- **SPA secret handling:** revealed secret rendered as **text** (not HTML), never in the URL, never in
  persistent storage; CSRF token in-memory only; session cookie HttpOnly; robust open-redirect validator.
- **Fork notes:** `rodauth-omniauth` is unmodified upstream v0.6.2; the `rodauth` fork carries upstream
  maintenance — all SSO risk is in OTS's own config overrides (A1/A2/A4).

---

## 5. Top remediation priorities

1. **[C1]** Make secret reveal/burn an **atomic single-winner consume** (Lua check-and-`DEL`-returning-
   ciphertext, or `WATCH`+`MULTI/EXEC` on the secret key, or `Familia::Lock`). The codebase already uses
   these primitives for org/domain creation — apply them to the crown-jewel path. Decrypt only after the
   atomic claim succeeds.
2. **[A1/A2/A4]** For SSO: require a verified-email claim (or out-of-band verification) before linking an
   SSO identity to an existing account; enforce the domain allowlist on the linking path; do not bypass
   MFA for `via_omniauth`.
3. **[S1/S2]** Ship CSP, `X-Frame-Options`/`frame-ancestors`, and HSTS **on by default**.
4. **[P1]** Apply CSRF protection (or strict same-origin/SameSite) to cookie-authenticated `/api/*` mutations.
5. **[D1]** Bump `oauth2 >= 2.0.22`.
6. **[A3/P2]** Pin Rodauth `base_url`/email host to a configured canonical host; align `DetectHost` with
   otto's trusted-proxy config.
7. **[D5]** Default Redis/Valkey to `requirepass`/ACL and not host-exposed; replace RabbitMQ `guest:guest`.

---

## 6. Caveats on scope of impact

- The default deployment has **authentication and SSO disabled** and **diagnostics off**, so A1/A2/A4/A6/A7/A8
  and D1 require those features to be enabled to be exploitable. They are nonetheless serious for the
  (common) hosted/enterprise configurations that enable accounts + SSO.
- C1 (one-time race), S1/S2 (headers), and C5 apply to the **default** configuration.
- Items marked NEEDS-VALIDATION (AZ3/AZ4/AZ5) are reachable model-layer weaknesses with no confirmed
  production sink today; they are pre-emptive hardening.
