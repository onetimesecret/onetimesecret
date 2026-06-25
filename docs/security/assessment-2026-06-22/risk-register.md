# OneTimeSecret — Risk Register (Prioritized)

Ratings: **Severity** = overall risk when the feature is enabled. **Exploitability** (Easy/Moderate/Hard)
= attacker effort/preconditions. **Business impact** (High/Med/Low) = consequence to the product's promise.
**Default?** = affects the out-of-the-box config (auth & SSO are OFF by default).
Status: ✅ confirmed (source) · 🧪 runtime-PoC · 🔎 needs-validation.

| ID | Finding | Sev | Exploit | Bus. impact | Default? | Status | Evidence |
|----|---------|-----|---------|-------------|----------|--------|----------|
| A1 | SSO email-match account takeover (no `email_verified`) | **Critical** | Moderate | High | No (SSO) | ✅ | 01; `config/hooks/omniauth.rb:27-30` |
| C1 | TOCTOU race — one-time guarantee broken | **High** | Moderate¹ | High | **Yes** | 🧪 | 03 F1; `secret_state_management.rb:60`; PoC `poc/`, `evidence/race_poc_output.md` |
| A2 | SSO + local MFA — add opt-in 2nd factor after SSO (default unchanged, reclassified after industry research: SSO-as-authenticated is the norm) | Low–Med | n/a² | Med | No (SSO+MFA) | ✅ | 01; `hooks/login.rb:128-133` |
| A3 | Host-header poisoning of reset/magic/verify links | **High** | Moderate | High | No (auth) | ✅ | 01/04; `detect_host.rb:156-194` |
| A4 | SSO domain allowlist not enforced on linking path | **High** | Moderate | High | No (SSO) | ✅ | 01; `hooks/omniauth.rb:133-180` |
| P1 | CSRF bypass for cookie-auth `/api/*` mutations | **High** | Moderate | High | No (login) | ✅ | 04; `security.rb:142` |
| S1 | CSP disabled by default | **High** | Moderate | Med | **Yes** | 🧪 | 05; `config.defaults.yaml:351`; `evidence/headers_output.md` |
| S2 | Clickjacking/HSTS/headers off by default | **High** | Moderate | Med | **Yes** | 🧪 | 05/04; `config.defaults.yaml:314-338`; `evidence/headers_output.md` |
| D1 | `oauth2` 2.0.18 bearer-token leak CVE | **High** | Moderate | High | No (SSO) | ✅ | 06; `Gemfile.lock:265` |
| C2 | Encryption HKDF salt = shared lib default | Medium | Hard | Med | Yes | ✅ | 03 F2; `configure_familia.rb:57-72` |
| C3 | V1 reveal: no passphrase rate limiting | Medium | Moderate | Med | Yes³ | ✅ | 03 F3; `v1/.../show_secret.rb:26-31` |
| P2 | `DetectHost` un-harmonized host trust | Medium | Hard | Med | Yes | ✅ | 04; `detect_host.rb:156-165` |
| P3 | Rate-limit gaps (login, secret create) | Medium | Easy | Med | Yes | ✅ | 04; `v1/controllers/base.rb:145-171` |
| AZ1 | RemoveMember authz inconsistency | Medium | Hard | Med | No (orgs) | ✅ | 02 F1 |
| AZ2 | Org safe_dump leaks internal/cross-tenant data | Medium | Easy⁴ | Med | No (orgs) | ✅ | 02 F2; `organization/.../safe_dump_fields.rb:17-29` |
| AZ3 | `Organization.create!` open splat (mass-assign) | Medium | Hard | Med | No (orgs) | 🔎 | 02 F3; `organization.rb:431-437` |
| AZ4 | `change_role!` accepts `owner` | Medium | Hard | Med | No (orgs) | 🔎 | 02 F4; `organization_membership.rb:258-274` |
| AZ5 | Org extid plain SHA-256 (no HMAC) | Medium | Hard | Low | No (orgs) | 🔎 | 02 F5; `organization.rb:46` |
| A5 | Recovery codes stored plaintext | Medium | Hard⁵ | High | No (auth) | ✅ | 01; `rodauth/.../recovery_codes.rb` |
| A6 | WebAuthn RP-ID/origin from `request.host` | Medium | Hard | Med | No (auth) | ✅ | 01; `features/webauthn.rb:14-22` |
| A7 | Reset enumeration + no max password length (Argon2 DoS) | Medium | Easy | Med | No (auth) | ✅ | 01; `features/account_management.rb:104` |
| A8 | 1-day per-account lockout (targeted DoS) | Medium | Easy | Med | No (auth) | ✅ | 01; `features/lockout.rb:15` |
| D2 | `form-data` 4.0.5 via axios (browser, mitigated) | Medium | Hard | Low | Yes | ✅ | 06; `pnpm-lock.yaml:3129` |
| D3 | Production source maps shipped/served | Medium | Easy | Low | Yes | ✅ | 06/05; `vite.config.ts:283` |
| D4 | Caddy proxy runs as root, unpinned base | Medium | Hard | Med | (Caddy variant) | ✅ | 06; `docker/variants/caddy.dockerfile:85` |
| D5 | Unauth Redis + host-exposed; RabbitMQ guest:guest | Medium | Moderate⁶ | High | (compose) | ✅ | 06; `docker-compose.simple.yml:57-69` |
| S3 | Revealed secret not cleared from SPA memory | Medium | Hard | Med | Yes | ✅ | 05; `secretStore.ts:203-216` |
| C4 | Passphrase rate-limit check/record non-atomic | Medium | Moderate | Med | Yes | ✅ | 03 F4 |
| C5 | No secret payload size cap (Redis DoS) | Low | Easy | Low | Yes | ✅ | 03 F5; `conceal_secret.rb` |
| C6 | Legacy v1 unsalted SHA-256 enc key (read-compat) | Low | Hard | Low | Yes | ✅ | 03 F6; `configure_familia.rb:65` |
| AZ6 | Receipt safe_dump exposes creator owner_id | Low | Easy | Low | Yes | ✅ | 02 F6 |
| AZ7 | show_invite discloses inviter email + account oracle | Low | Easy | Low | No (invites) | ✅ | 02 F7; `invite/logic/base.rb:51-64` |
| AZ8 | Customer.create! no allowlist (safe today) | Low | Hard | Med | Yes | 🔎 | 02 F8; `customer.rb:271-313` |
| AZ9 | No rate limit on anonymous incoming `/secret` (emails) | Low | Easy | Low | No (incoming) | 🔎 | 02 F9 |
| P4 | V1 Basic-Auth username enumeration via timing | Low | Hard | Low | No (auth) | ✅ | 04; `v1/controllers/base.rb:68-71` |
| P5 | Log injection of Basic-Auth username | Low | Easy | Low | No (auth) | ✅ | 04; `v1/controllers/base.rb:67` |
| S4 | `v-html` in GlobalBroadcast (sanitized) | Low | Hard | Low | Yes | ✅ | 05; `GlobalBroadcast.vue:139` |
| S5 | DNS widget script injected without nonce | Low | Hard | Low | No (domains) | 🔎 | 05; `useDnsWidget.ts:155-163` |
| OBS1 | SessionDebugger dumps Set-Cookie when enabled | Info | Hard | Low | No | ✅ | 06; `session_debugger.rb:102` |

**Footnotes**
1. C1 is Easy under production multi-worker Puma (PoC: 12/12 processes); Hard within a single GIL-bound process.
2. A2 reclassified Low–Med: treating SSO as fully authenticated (no local 2nd factor) is the industry default (WorkOS exempts SSO from MFA; Clerk/others defer to IdP MFA) and was an intentional choice (#3114). The fix is an *opt-in* "require local MFA after SSO" toggle (default off) for high-assurance operators — not a default change.
3. C3 default-applicable only if the V1 API remains routable.
4. AZ2 requires being any active member of the target org.
5. A5 requires DB read access; impact is high because codes are the MFA fallback.
6. D5 Moderate if the compose network/host is reachable; the simple compose publishes 6379 to the host.

## Suggested sprint ordering
1. **Now:** C1 (atomic consume), S1/S2 (secure headers default-on), D1 (oauth2 bump).
2. **Next (if accounts/SSO offered):** A1, A2, A4, A3/P2, P1.
3. **Hardening:** C2, C3, P3, AZ1/AZ2, A5/A6/A7/A8, D3/D4/D5.
4. **Cleanup / pre-emptive:** C4/C5/C6, AZ3/AZ4/AZ5/AZ8, P4/P5, S3/S4/S5.
