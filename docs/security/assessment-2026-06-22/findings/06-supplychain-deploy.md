# Security Assessment — Supply Chain, Runtime/Deployment & Secrets Handling

**Target:** OneTimeSecret (`/home/user/onetimesecret`, branch `claude/vigilant-goldberg-97ijfl`, commit `ef971b0`)
**Supporting gems (local):** `/home/user/otto` (2.3.1), `/home/user/familia` (2.10.1), `/home/user/rodauth` (2.42.0), `/home/user/rodauth-omniauth` (0.6.2)
**Scope:** Dependency vulns, lockfile integrity, container hardening, secrets handling, config drift/deployment, sensitive-data logging, install scripts
**Date:** 2026-06-22
**Reviewer:** Automated defensive security assessment (authorized, read-only on tracked source)

## Tooling status

Outbound internet was **available** (not loopback-restricted). Both scanners ran against fresh advisory databases:

- `bundler-audit` 0.9.3, ruby-advisory-db updated 2026-06-22 (1158 advisories). **CONFIRMED via tooling.**
- `pnpm audit` (pnpm 11.8.0, Node 22.22.2) reached the GitHub advisory DB. **CONFIRMED via tooling.**

All CVE/GHSA findings below are tooling-confirmed unless explicitly marked knowledge-based.

---

## Summary of findings by severity

| # | Severity | Finding | Evidence |
|---|----------|---------|----------|
| 1 | HIGH | `oauth2` 2.0.18 — bearer token leak via protocol-relative redirect (reachable in SSO path) | Gemfile.lock:265 |
| 2 | HIGH | `form-data` 4.0.5 (via `axios`) — CRLF injection; **prod dep tree** (mitigated: axios runs client-side) | pnpm-lock.yaml:3129 |
| 3 | MEDIUM | Source maps (`.js.map`) built and shipped/served in production at `/dist` | vite.config.ts:283; static_files.rb:67; fly.toml `[[statics]]` |
| 4 | MEDIUM | Caddy proxy image runs as **root**, base image **not digest-pinned**, no `--no-install-recommends` | docker/variants/caddy.dockerfile:85 (no USER) |
| 5 | MEDIUM | Redis/Valkey runs with **no `requirepass`/ACL** and `--bind 0.0.0.0`; simple compose **publishes 6379 to host** | docker/compose/docker-compose.simple.yml:62-71 |
| 6 | MEDIUM | RabbitMQ defaults to `guest:guest` in full compose | docker/compose/docker-compose.full.yml `RABBITMQ_*` |
| 7 | LOW | Dev/test-only JS CVEs: `ws` (High DoS), `undici` (High DoS), `esbuild`, `@babel/core`, `js-yaml`, `markdown-it` | pnpm-lock.yaml |
| 8 | LOW | `SessionDebugger` logs full response headers (incl. Set-Cookie) when `DEBUG_SESSION` set | apps/web/core/application.rb:50; session_debugger.rb:102 |
| 9 | LOW | Legacy v1 encryption key = unsalted single-round `Base64(SHA256(secret))` | configure_familia.rb:65 |
| 10 | INFO | `redis://CHANGEME@…` default URI is only a WARNING in one path, hard error in another | configure_familia.rb:38 vs check_redis_url.rb:23 |

**Positive controls observed (no action needed):** `SECRET` has no insecure default and the app fails closed if missing (config.defaults.yaml:11, configure_familia.rb:25); secrets generated with `SecureRandom.hex(64)` + HKDF (init.rake:116,126); `.env` chmod 600 by installer (install.sh:163,205); main app/S6 images run as non-root UID 1001 and are digest-pinned; CI/test images digest-pinned; no `curl|bash`; no committed `.env`/private keys/production secrets; well-designed route-annotation-driven Sentry URL scrubbing; diagnostics, SSO, CSP, regions all default OFF.

---

## 1. Dependency vulnerabilities

### 1.1 [HIGH — CONFIRMED] `oauth2` 2.0.18 — bearer Authorization leak via protocol-relative redirect
- **Evidence:** `Gemfile.lock:265` `oauth2 (2.0.18)`. GHSA-pp92-crg2-gfv9. Fixed in `>= 2.0.22`.
- **Impact:** `OAuth2::Client#request` honours a protocol-relative `Location` (`//attacker.example`) and re-sends the bearer `Authorization` header to the attacker-controlled host. `oauth2` is pulled by `omniauth-oauth2 (1.9.0)` / `omniauth-google-oauth2 (1.2.2)` (Gemfile.lock:288-295) and is **reachable in production** for any deployment that enables SSO/OmniAuth login (`apps/web/auth/config/features/omniauth.rb`, `apps/web/auth/config/hooks/omniauth.rb`). For installs with SSO disabled (the default, `AUTH_ENABLED`/SSO off) the code path is not exercised.
- **Remediation:** `bundle update oauth2` to `>= 2.0.22`. The dependency constraint `oauth2 (>= 2.0.2, < 3)` (Gemfile.lock:294) permits this with no manifest change.

### 1.2 [HIGH — CONFIRMED, partially mitigated] `form-data` 4.0.5 (transitive via `axios`)
- **Evidence:** `pnpm-lock.yaml:3129` `form-data@4.0.5`. GHSA-hmw2-7cc7-3qxx. Fixed in `>= 4.0.6`. `pnpm audit --prod` reports this as the **only production-tree** JS finding; paths `.>axios>form-data` and `.>@vueuse/integrations>axios>form-data`.
- **Impact:** CRLF injection via unescaped multipart field names/filenames. **Mitigation:** `axios` is consumed only by the **browser** bundle (`src/shared/stores/*`, `src/shared/composables/useApi.ts`); `form-data` is axios's Node-runtime multipart helper and is not used by the browser XHR/fetch adapter, so practical exploitability in this app is low. Still flagged HIGH by the scanner and should be patched as defence-in-depth and to clear the prod-tree alert.
- **Remediation:** Bump `axios` (`^1.16.0` → latest 1.x) so it resolves `form-data >= 4.0.6`; or add a pnpm `overrides` entry `"form-data": ">=4.0.6"` in `pnpm-workspace.yaml` (note: existing overrides block already present).

### 1.3 [LOW — CONFIRMED] Dev/test-only JS advisories (not in production image)
The production Docker build runs `pnpm prune --prod` and deletes `node_modules` (Dockerfile:149-151); the runtime image ships no JS deps. These affect only the build/CI/dev host:
- `ws` 8.19.0 — **High** DoS (GHSA-96hv-2xvq-fx4p) + moderate memory disclosure (GHSA-58qx-3vcg-4xpx); via vitest/jsdom/happy-dom. (pnpm-lock.yaml:4960)
- `undici` 6.24.1 — **High** WebSocket DoS (GHSA-vxpw-j846-p89q) + 3 lower; via `@sentry/cli`. (pnpm-lock.yaml:4596)
- `esbuild` 0.27.7 — Low dev-server file read on Windows (GHSA-g7r4-m6w7-qqqr). (pnpm-lock.yaml:2849)
- `@babel/core <=7.29.0`, `js-yaml <=4.1.1` ReDoS, `markdown-it <=14.1.1` ReDoS — all dev-tree.
- **Remediation:** Refresh dev toolchain (`pnpm update` for vitest/jsdom/happy-dom/@sentry/cli/esbuild). Low priority; no production exposure.

### 1.4 Security-critical pinned versions (manually reviewed, no known-bad)
`rack 3.2.6`, `puma 7.2.1`, `nokogiri 1.19.4`, `sanitize 7.0.0`, `json_schemer 2.5.0`, `json-jwt 1.17.0`, `jwt 3.2.0`, `rack-oauth2 2.3.0`, `openid_connect 2.3.1`, `webauthn 3.4.3`, `sequel 5.102.0`, `redis 5.4.1`, `stripe 18.4.2`, `sentry-ruby 6.5.0`, `omniauth 2.1.4` — none flagged by ruby-advisory-db (1158 advisories). Frontend: `vue 3.5.34`, `vite 8.0.16`, `dompurify 3.4.11` — clean. `oauth2` (1.1) is the only flagged Ruby gem.

---

## 2. Lockfile integrity & build provenance

- **Both lockfiles present and self-consistent** with manifests (`Gemfile`/`Gemfile.lock`, `package.json`/`pnpm-lock.yaml` v9.0). Docker builds use `--frozen-lockfile` (Dockerfile:93) and `bundle install` against the committed lock.
- **Git source — ACCEPTABLE:** `Gemfile:165,174` pulls `rspec` (+ subgems) from `git: https://github.com/rspec/rspec` pinned to revision `1559574…` (Gemfile.lock:3). This is the **canonical rspec org** repo at a 4.0.0.beta1 prerelease, and it is **test-group only** (excluded from the prod image via `BUNDLE_WITHOUT="development:test:optional"`, Dockerfile:84). Low risk, but pinning a beta from git for a test dep is a minor provenance smell — prefer a released gem when available.
- **No path:/fork/non-canonical Ruby sources.** No git/tarball resolutions in `pnpm-lock.yaml`; default npmjs registry; `.npmrc` carries no auth tokens or alternate registry.
- **pnpm `overrides` (pnpm-workspace.yaml:7-11):** `brace-expansion` pinned to `1.1.13` (patched past CVE-2024-4068 ReDoS — good), plus `yaml`, `@types/estree`, `flatted`. Benign hardening.
- **NEEDS-VALIDATION:** `.npmrc` does **not** set `ignore-scripts`, and `pnpm-workspace.yaml:1-6 allowBuilds` permits postinstall builds for `@sentry/cli`, `esbuild`, `unrs-resolver`. Standard for these packages, but lifecycle scripts run at install — a supply-chain vector if any of those packages were compromised. Consider `ignore-scripts=true` + explicit allowlist if threat model warrants.

---

## 3. Container hardening

**Main image (`Dockerfile`) — strong:**
- Non-root `appuser` UID/GID 1001, `/sbin/nologin` (Dockerfile:237-238, 303, 348-349, 407).
- Base images **digest-pinned**: `ruby:3.4-slim-trixie@sha256:3f33…` (Dockerfile:62), node/ruby in base.dockerfile:23-24, S6 overlay version-pinned (Dockerfile:193). Dockerfile syntax frontend digest-pinned (Dockerfile:1).
- Multi-stage: build deps dropped; `bundle clean --force`, `pnpm prune --prod`, `rm -rf node_modules ~/.npm ~/.pnpm-store`, `npm uninstall -g pnpm` (Dockerfile:89,149-151). `apt` uses `--no-install-recommends` + `rm -rf /var/lib/apt/lists/*` (Dockerfile:205-213, 331-338).
- No secrets baked into ENV/layers — `SECRET`/`SESSION_SECRET` are injected at runtime only (documented in header, Dockerfile:33-47). Only `EXPOSE 3000`.

**Finding 4 — [MEDIUM] Caddy variant proxy is poorly hardened (`docker/variants/caddy.dockerfile`):**
- **Runs as root** — no `USER` directive anywhere (`grep -c USER` = 0). This is the **internet-facing TLS-terminating proxy** in the full stack.
- **Base image not digest-pinned:** `FROM debian:bookworm-slim` (line 85) — floating tag, undermines reproducibility/supply-chain integrity (contrast: builder stage `golang:1.26-bookworm@sha256:…` line 61 *is* pinned).
- `apt-get install` lacks `--no-install-recommends` (lines 90-96), pulling extra packages (curl, bind9-dnsutils, iputils-ping, netcat — also broadens attack surface in a prod proxy).
- Copies `./public/web` into the served root (line ~112), which includes the `.js.map` source maps (see Finding 3).
- **Remediation:** add a non-root `USER`; digest-pin `debian:bookworm-slim`; add `--no-install-recommends`; drop debugging tools (netcat/ping/dig) from the production proxy image; exclude `.map` files from copied assets.

**`.dockerignore` (`/home/user/onetimesecret/.dockerignore`) — good:** excludes `**/.env*`, `.git`, `.certs/`, `data/`, `*.rdb`, `Caddyfile`, `fly.toml`, and the rendered `etc/config.yaml`/`etc/auth.yaml`/`etc/billing.yaml` (lines 1-40) — prevents leaking host secrets/config into build context.

---

## 4. Secrets handling

**Strong overall — no hardcoded production secrets found in any of the 5 repos.**

- **Root `SECRET` fails closed:** `config.defaults.yaml:11 secret: <%= ENV['SECRET'] || nil %>` (no insecure fallback). `set_secrets.rb:39` returns `nil` if unset; `configure_familia.rb:25` **raises `'site.secret not set or empty'`** — the app will not boot without a real secret. CONFIRMED.
- **Secret generation is sound:** `init.rake:116 SecureRandom.hex(64)` for root SECRET; derived keys via HKDF (`Onetime::KeyDerivation.derive_hex`, init.rake:126); independent secrets (`AUTH_SECRET`, `ARGON2_SECRET`) via `SecureRandom.hex` (init.rake:134). `.env` chmod 600 (install.sh:163,205).
- **No committed secrets:** no `.env`/`.env.local`/`*.pem`/`*.key`/`id_rsa` tracked across all repos; `.env.example`/`.env.reference` ship **empty** secret values. The only private-key block is `familia/examples/encrypted_fields.rb` — an explicit example using `Base64('example-encryption-key-version-1')`, not a real key.
- **Finding 9 — [LOW] Weak legacy KDF:** `configure_familia.rb:65 v1_key = Base64.strict_encode64(Digest::SHA256.digest(secret_key))` — a single unsalted SHA-256 round. This is **legacy read-compat only** (v2 is HKDF and is `current_key_version`, line 72), so new writes are safe, but legacy ciphertext remains protected by a weak derivation. Acceptable as a migration bridge; track for eventual removal once legacy data is re-encrypted.
- AWS/SMTP/OAuth/Stripe credentials are all `ENV`-sourced with `nil` defaults (config.defaults.yaml, mailer.rb:305, ses.rb:63). `FROM_EMAIL` and emailer default to harmless `CHANGEME@example.com` placeholders.

---

## 5. Config drift / deployment

**Finding 5 — [MEDIUM] Redis/Valkey unauthenticated + host-exposed:**
- `docker/compose/docker-compose.simple.yml:35-71` runs valkey with `--bind 0.0.0.0`, **no `requirepass`/ACL**, and **publishes `6379:6379` to the host** (line 70). On a host without an external firewall, the secret store (encrypted secrets, sessions) is reachable on the LAN/host with no auth.
- `etc/examples/valkey.conf:7` ships `#requirepass CHANGEME` **commented out** (default = no password); the example does `bind 127.0.0.1` (line 9) but the compose command overrides to `0.0.0.0`.
- App-side `REDIS_URL` default `redis://127.0.0.1:6379/0` has no password (.env.example), and the YAML fallback is `redis://CHANGEME@127.0.0.1:6379` (config.defaults.yaml:557).
- The **full** stack (docker-compose.full.yml) is better — valkey is `expose`-only (not published) on an internal bridge network — but still has no `requirepass`.
- **Remediation:** set `requirepass`/ACL on valkey and a password in `REDIS_URL`; in simple compose bind to the docker network and do not publish 6379 to the host (or bind to `127.0.0.1:6379:6379`).

**Finding 6 — [MEDIUM] RabbitMQ default `guest:guest`:**
- `docker-compose.full.yml` sets `RABBITMQ_DEFAULT_USER=${RABBITMQ_USER:-guest}` / `RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASS:-guest}` and worker/scheduler `RABBITMQ_URL=amqp://${RABBITMQ_USER:-guest}:${RABBITMQ_PASS:-guest}@rabbitmq:5672`. The YAML default is `amqp://guest:guest@localhost:5672/dev` (config.defaults.yaml:778). Ports are `expose`-only (not host-published), so blast radius is the internal network, but default creds are still poor hygiene.
- **Remediation:** require `RABBITMQ_USER`/`RABBITMQ_PASS` (use `:?` like `SECRET`), document credential rotation.

**fly.toml — good:** `force_https = true`, secrets via fly vault (`fly secrets set`), `RACK_ENV=production`, `CSP_ENABLED=true`. `tls_skip_verify=true` (line in `[[http_service.checks]]`) is only on the internal localhost health check — acceptable.

**Diagnostics / Sentry — good:** `diagnostics.enabled` defaults **false** (config.defaults.yaml:982); all Sentry DSNs default `nil` (lines 1001-1028). DSN is only previewed (first 11 chars) in logs (setup_diagnostics.rb:66). Strict trace continuation supported. No DSN leakage.

**Finding 3 — [MEDIUM] Source maps shipped to production:**
- `vite.config.ts:283 sourcemap: true` with `outDir: '../public/web/dist'` (line 240). The Dockerfile copies all of `public/` into the final image (Dockerfile:245,356) with **no `.map` stripping** (none in Dockerfile or `.dockerignore`). `Onetime::Middleware::StaticFiles` serves `/dist` from `public/web` with no extension filter (static_files.rb:67,75), and `fly.toml [[statics]]` serves `/app/public/web/dist` at `/dist`. The Caddy variant also copies `public/web` to its served root.
- The in-code comment "Sentry sourcemaps are uploaded via CI, not at build time" (vite.config.ts:219) refers to *upload* to Sentry — it does **not** prevent the `.map` files from being emitted to disk and served. Result: minified frontend source maps are publicly retrievable at `/dist/*.js.map`, disclosing original TypeScript/Vue source structure.
- **Severity rationale:** MEDIUM — it's a client-side bundle (no server secrets in it), but it eases reconnaissance of client logic/endpoints. **NEEDS-VALIDATION** that a built image actually serves `200` for a `.map` URL (build not executed here).
- **Remediation:** set `build.sourcemap: 'hidden'` (emits maps + references for Sentry upload but strips the `//# sourceMappingURL` comment) or delete `*.map` after Sentry upload in CI / before packaging; alternatively add `*.map` to `.dockerignore`-equivalent post-build cleanup and exclude from the Caddy `COPY`.

**CORS / host allowlist:** `development.frontend_host` defaults to `http://localhost:5173` but the ViteProxy middleware is only mounted in `Onetime.development?` (application.rb:45-48), not production. No permissive CORS/`Access-Control-Allow-Origin: *` defaults found.

---

## 6. Logging of sensitive data

- **Sentry URL scrubbing — well-designed:** `setup_diagnostics.rb:280-411` redacts secret/receipt/metadata/incoming identifiers, auth-token paths (`/forgot`, `/auth/reset-password`, `/account/email/confirm`), colonel admin paths, and query params (`key/secret/token/passphrase`), with fail-closed `[SCRUBBING_FAILED]` on error. `scripts/generate-sentry-scrub-patterns.ts` derives the frontend scrub patterns from route annotations (`sensitive=true`) and validates that each produces capture groups — good drift protection.
- **Finding 8 — [LOW] `SessionDebugger` logs full response headers when enabled:** `apps/web/core/application.rb:50 use Rack::SessionDebugger if ENV['DEBUG_SESSION']`. When `DEBUG_SESSION` is truthy, `session_debugger.rb:98-103` logs `response_headers: headers` at debug — this includes `Set-Cookie` (the session cookie). The middleware does take care to discard the cookie *value* in `log_cookies` (line 247) and obscures `email` (line 145), but the wholesale `response_headers` dump at line 102 re-introduces the full `Set-Cookie`. **Gated/off by default** and only in development mounting, so LOW. **Remediation:** filter `set-cookie`/`authorization` out of the `response_headers` dump.
- **`HeaderLoggerMiddleware`** (logs all headers incl. Cookie/Authorization) carries an explicit SECURITY WARNING and is **not mounted anywhere** — documentation-only (grep shows no `use` outside its own doc comment). No action needed beyond keeping it unwired.
- No evidence of logging raw secret bodies, passphrases, or full request bodies in production code paths. `OT.ld` redacts the Redis password in `check_redis_url.rb:31` (`:***@`).

---

## 7. Install scripts

- **No `curl|bash`, no insecure downloads.** `install.sh` `eval` usage (lines 29,36,50,57) is confined to internal version-extractor command strings (`ruby -e "puts RUBY_VERSION"`), not network input.
- Secrets generated via `bundle exec rake ots:secrets` (`SecureRandom`/HKDF) and `.env` immediately `chmod 600` (install.sh:163,205). Refuses to proceed if `SECRET` is empty (install.sh:157,212).
- `install-dev.sh:159-160` prompts for `sudo` only to symlink a Caddy parent dir — scoped and interactive. `install-test.sh` reviewed: no risky patterns.
- The S6 Dockerfile and caddy builder download S6/xcaddy over **HTTPS from pinned GitHub release tags** (Dockerfile:225-226) — acceptable, though not checksum-verified (minor: consider verifying the S6 release SHA256).

---

## Recommended remediation priority

1. **HIGH:** `bundle update oauth2` to `>= 2.0.22` (Finding 1) — only real production-reachable code vuln (SSO deployments).
2. **HIGH:** Bump `axios`/override `form-data >= 4.0.6` (Finding 2) — clears prod-tree alert.
3. **MEDIUM:** Set `sourcemap: 'hidden'` and stop shipping `.map` to prod / Caddy (Finding 3).
4. **MEDIUM:** Harden the Caddy proxy image — non-root USER, digest-pin debian, `--no-install-recommends`, drop debug tools (Finding 4).
5. **MEDIUM:** Add `requirepass`/ACL to valkey and stop publishing 6379 to the host in simple compose (Finding 5); require non-default RabbitMQ creds (Finding 6).
6. **LOW:** Refresh dev JS toolchain (Finding 7); filter Set-Cookie from SessionDebugger response-header dump (Finding 8); plan removal of legacy v1 SHA-256 KDF (Finding 9).
