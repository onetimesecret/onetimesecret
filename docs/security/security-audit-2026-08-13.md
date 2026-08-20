# Security & Code Audit — 2026-08-13

- **Repo:** onetimesecret/onetimesecret (siblings checked for delta: familia, otto, rodauth, rodauth-oauth, rodauth-omniauth, rodauth-tools, omniauth)
- **Method:** Automated single-agent audit, delta-focused against the 2026-08-06 audit. Reviewed the 448 commits landed since 2026-08-06 (HEAD `ae4a00a0`), concentrating on the largest new attack surfaces in the window: the WebAuthn/passkey feature (#4130), the shared SSRF egress guard (`Onetime::Http::Guard`) and its consumers, the SMTP2GO mail provider (#4141/#4145), the `trusted_proxy.mode` single-accessor work (#4087), the admin host/network isolation gates (#4062/#4127/#4131), the domain `restrict_to` work (ADR-024 amendments), the Stripe currency-migration/refund path (#4025/#4043/#4048), and the link-domains pool at secret creation (#4063). Every finding below was verified by reading current source, not inferred from commit messages.
- **Out of scope by instruction:** dependency/CVE triage (handled by Renovate + Dependabot). No tickets filed.

---

## Bottom line

Three new findings, one of them High. The High is a fail-open environment-variable coercion that silently disables TLS certificate verification on the RabbitMQ connection — a channel that carries secret retrieval keys in its payloads. The other two are Low. No Critical.

The delta's most security-sensitive new code — the SSRF guard, the admin isolation gates, and the trusted-proxy accessor — held up under review; notes are in "Reviewed, no issue found". The domain `restrict_to` enforcement gap is real but is already documented, decided, and tracked in ADR-024 A1, so it is recorded below as *known and tracked*, not re-filed as a finding.

---

## Findings

### 1. HIGH — `RABBITMQ_VERIFY_PEER` fails open: any spelling other than the literal `'true'` silently disables AMQPS certificate verification

**Location:** `lib/onetime/jobs/queues/config.rb:184` (`Onetime::Jobs::QueueConfig.tls_options`)

```ruby
options = {
  tls: true,
  verify_peer: ENV.fetch('RABBITMQ_VERIFY_PEER', 'true') == 'true',
}
```

**Description:** The default is correct (unset ⇒ `'true'` ⇒ verification on), but the coercion is an exact string equality against `'true'`, so **every other spelling evaluates to `false`**. `RABBITMQ_VERIFY_PEER=TRUE`, `True`, `1`, `yes`, or a value with stray whitespace all disable peer verification. An operator who sets the variable *intending to enforce* verification gets the opposite, with no warning, no boot error, and no log line — the connection still succeeds, so nothing surfaces the downgrade.

The polarity is what makes this dangerous. The same `== 'true'` idiom is used elsewhere in the codebase (e.g. `AUTH_WEBAUTHN_VERIFY_ACCOUNT`, `AUTH_WEBAUTHN_AUTOFILL`) where the default is OFF and only the literal `'true'` enables — there, a misspelling fails *closed*. This is the only instance found where the pattern is applied to a default-ON security control, and it is therefore the only one that fails open. The codebase's own ratified standard points the other way: ADR-033 (fail-fast-and-loud), and commit `508d018c` ("fix(billing): raise on unrecognized boolean env flags instead of silently disabling") fixed exactly this bug class in billing during this same window. The sibling flags that got the safe treatment use the `!= 'false'` form (`ENV['SMTP_TLS'] != 'false'`, `AUTH_LOCKOUT_ENABLED`, `AUTH_PASSWORD_REQUIREMENTS_ENABLED`, `AUTH_ACTIVE_SESSIONS_ENABLED`, `AUTH_REMEMBER_ME_ENABLED`).

**Why this is High rather than Low:** the affected channel is not incidental. The AMQP payloads carry secret material — `lib/onetime/jobs/workers/email_worker.rb:24-25` documents the email job shape as `"data": { "secret_key": "abc123", "share_domain": null, "recipient": "user@example.com", "sender_email": "..." }`. With `verify_peer: false` on an `amqps://` connection, the TLS session is established but the broker's certificate is not validated against a CA, so an attacker positioned between the app and a managed broker (CloudAMQP, Northflank — precisely the deployments that use `amqps://`) can terminate the connection with any certificate and read secret retrieval keys and recipient addresses in cleartext, or inject jobs.

Exploitation requires the operator to have written a non-canonical spelling, so this is a misconfiguration amplifier rather than a default-state vulnerability. That is the same shape as a fail-open allowlist typo, and this codebase already treats that shape as unacceptable everywhere else (see `AdminNetworkIsolation#configured_host_gate`, which denies rather than self-disables on an unenforceable list).

**Recommended fix:** Parse the flag the way the rest of the codebase does and refuse to guess. Either adopt the safe polarity —

```ruby
verify_peer: ENV.fetch('RABBITMQ_VERIFY_PEER', 'true').to_s.strip.downcase != 'false',
```

— or, preferably and consistent with `508d018c` and ADR-033, route it through the shared strict boolean coercion and **raise at boot** on an unrecognized value, so a typo is a loud deploy-time failure instead of a silent runtime downgrade. Whichever is chosen, log the resolved TLS posture at boot alongside the broker URL host (credentials redacted), so `verify_peer: false` is visible in the same way `AdminNetworkIsolation#log_boot_posture` makes the admin gates visible.

---

### 2. LOW — MFA-incomplete sessions can call the `/auth/*` account JSON routes, including a state-changing session purge

**Locations:** `apps/web/auth/routes/active_sessions.rb:11`, `apps/web/auth/routes/active_sessions.rb:105`, `apps/web/auth/routes/account.rb:72,89,156`, `apps/web/auth/routes/identities.rb:31`, `apps/web/auth/routes/webauthn_credentials.rb:42`; route tree at `apps/web/auth/router.rb:172-185`

**Description:** All seven of these hand-written Roda routes gate on `rodauth.logged_in?`, which in Rodauth is `!!session[session_key]` — set by `login_session` at **first-factor** completion. An account with MFA enrolled therefore satisfies `logged_in?` while still only partially authenticated (`two_factor_authenticated?` is false, and the app's own `session['awaiting_mfa']` is still true). These are app routes in the auth router's own route tree, not Rodauth routes, so Rodauth's two-factor `before` guard does not cover them, and `apps/web/auth/router.rb` adds no wrapping check.

The consequence is that an attacker holding a victim's **password but not their second factor** can, from the half-authenticated session:

- `POST /auth/remove-all-active-sessions` (`active_sessions.rb:104-110`) → `remove_all_active_sessions_except_current`, terminating every one of the victim's real sessions on every device while the attacker's own partially-authenticated session, being "current", survives;
- remove an individual session (`active_sessions.rb:11`);
- read `GET /auth/account` and `/auth/account.json` (`account.rb:156`, `:72`) → email, verification status, `mfa_enabled`, `recovery_codes_count`, `active_sessions_count`, `passkeys_count`;
- enumerate linked SSO identities (`identities.rb:31`) and passkey credential IDs with last-use timestamps (`webauthn_credentials.rb:42`).

This is not account takeover — the attacker cannot complete login, change credentials, or read secrets — so the practical impact is forced-logout denial of service plus account-posture reconnaissance that tells an attacker exactly which second factor to target next.

Note the relationship to the 2026-07-06 audit's **M-11**, which is recorded as Fixed in `02dd1b21d`. That fix added the `awaiting_mfa` check to `BaseSessionAuthStrategy` — the **Onetime app session** path. It does not reach this surface, which reads the **Rodauth session** through `rodauth.logged_in?`. The guard exists and is simply not applied here; this is the uncovered half of M-11, not a regression of it.

One caveat against a blanket fix: `GET /auth/mfa-status` (`account.rb:89`) is legitimately needed *before* MFA completes — it is what drives the MFA challenge page toward the right route. Any hardening must keep that endpoint reachable pre-MFA.

**Recommended fix:** Introduce a single shared helper in the auth router (e.g. `fully_authenticated?` = `rodauth.logged_in? && !rodauth.two_factor_partially_authenticated?`, or the equivalent `session['awaiting_mfa'] != true` check the app session strategy already uses) and apply it to every route in this tree **except** `mfa-status`. Doing it as one helper rather than seven inline edits keeps this from drifting again the next time a route is added — the same discipline ADR-024 A2 applies to `restrict_to` resolution. At minimum, gate the two state-changing session-removal endpoints, which are the only ones with side effects.

---

### 3. LOW — SMTP2GO provider error bodies reach logs and Sentry unredacted, bypassing the redaction the sibling path applies

**Locations:** `lib/onetime/mail/smtp2go_client.rb:118-147` (`handle_response`), `lib/onetime/mail/delivery/smtp2go.rb:58-87` (`log_error`)

**Description:** `Delivery::Smtp2go` implements a deliberate redaction discipline: `perform_delivery` (`smtp2go.rb:46,51`) runs both the failure string and the serialized response through `redact_emails` before putting them in an `APIError`, because — as the comment states — "Failure strings embed the raw recipient address; redact it so the obscure_email discipline holds when log_error and Sentry pick up the message and response_body." Commit `b319c295` added this.

The redaction covers only the `E_DeliveryFailures` path, i.e. errors that `Delivery::Smtp2go` raises itself. Errors raised one layer down in `Smtp2goClient#handle_response` — every non-2xx response, and every 2xx carrying an error envelope — attach the **raw** provider body:

```ruby
raise APIError.new(message, status_code: code, error_code: error_code, response_body: body[0, 500])
```

`Delivery::Smtp2go#log_error` then writes that unmodified into `details`, emits `details.inspect` through `OT.le`, and attaches it to Sentry as the `smtp2go_error` context (`smtp2go.rb:61-74`) — directly alongside an `email` context in which `to:` is carefully passed through `obscure_email`. The result is one Sentry event that obscures the recipient in one field and may carry it in cleartext in the next.

The body is provider-controlled text, so what it contains is not fully under our control; SMTP2GO's validation errors (`E_ApiResponseCodes.NON_VALIDATING_IN_PAYLOAD` and friends) report which payload field failed, and the payload built at `smtp2go.rb:139-157` consists of `sender`, `to`, `subject`, `text_body`, `html_body`, and `Reply-To`. The exposure is therefore recipient/sender addresses and potentially a subject-line fragment leaking into log aggregation and Sentry — a PII-in-logs issue, not a secret-material one (the secret URL lives in the body, past the 500-character truncation in most cases, but truncation is not a control).

**Recommended fix:** Move the redaction to the boundary where the untrusted text enters, not the call site that happens to remember. Either apply `redact_emails` in `Delivery::Smtp2go#log_error` to `error.response_body` and `error.message` before they reach `OT.le`/Sentry (covers both raise paths with one change), or have `Smtp2goClient` accept an optional sanitizer that `Delivery::Smtp2go` supplies. The first is smaller and cannot be forgotten by a future third caller of the client. Consider whether `response_body` needs to reach Sentry at all, given `error_code` and `status_code` are already carried separately.

---

## Known and tracked — deliberately not re-filed

- **Domain `restrict_to` is display-only, with no server-side enforcement.** `AuthConfig#restrict_to` (`lib/onetime/auth_config.rb:207-227`) and `ConfigSerializer#resolve_restrict_to` shape the login page; nothing in `apps/web/auth/` rejects a crafted POST of a suppressed method. This is exactly the gap ADR-024 amendment **A1** documents ("Current state, for the record: display-only… Enforcement is follow-up work to PR #4130; until it ships, domain `restrict_to` must not be documented as an access control"), along with A2 (model-owned resolver), A3 (fail-closed degradation), A5 (custom-domain webauthn pending #4137), and A6 (account↔domain identity scope, #4138). Decided, scoped, and tracked — re-filing it would be noise.
- **Forwarded-host trust heuristic (#4024).** `Rack::DetectHost` lets any private/loopback peer name the host when `trusted_proxy` is unset. Documented at length in `lib/onetime/middleware/admin_network_isolation.rb:74-115`, which declines to rely on it and fails closed instead. Project-wide, known, tracked.
- **Federated subscription claim without email verification.** `apps/web/auth/operations/create_default_workspace.rb:314-333` carries an explicit "SECURITY AUDIT (verify-disabled residual)" block that logs loudly rather than blocking, on the stated grounds that blocking would silently disable federation for verify-disabled deployments. Deliberate, annotated, unchanged in this window.
- **Trusted-proxy depth mode correctness (#4024).** Called out as "currently broken" in `admin_network_isolation.rb:982`. Not re-derived here.

---

## Observations (no action required, recorded so they are not re-derived)

- **A passkey first factor satisfies MFA even without user verification.** `apps/web/auth/config/features/webauthn.rb` sets `webauthn_login_user_verification_additional_factor? true` (the native, UV-attested half), and `apps/web/auth/config/hooks/login.rb:180-182` extends the same treatment to the non-UV residual via `two_factor_update_session('webauthn-verification')`. The comment states this is deliberate: "possession + local gesture is the accepted bar." The consequence, stated plainly for the record: for an account that also has OTP enrolled, possession of a **PIN-less security key** alone yields a fully two-factor-authenticated session without the password or the OTP. That is a coherent policy, and the hook's justification (avoiding walling a passkey login behind a second factor it cannot complete) is sound. The only gap worth considering is disclosure — nothing tells a user enrolling a non-UV key that doing so makes that key a single-factor path past their OTP.
- **`webauthn_rp_id` derives from `request.host`.** Known and analysed in ADR-024 A5; credentials are only ever registered on the canonical host and `account_webauthn_keys` has no rp_id column, with per-domain scoping tracked in #4137. Phishing resistance is intact (browsers enforce rpId/origin binding); the limitation is functional reach, not a bypass.

---

## Reviewed, no issue found

- **`Onetime::Http::Guard` (new shared SSRF egress guard, `lib/onetime/http/guard.rb`).** Deny-by-default range union, fails closed on unparseable input (so `2130706433` / `0x7f000001` encoded-loopback smuggling is blocked rather than resolved), rejects a host if **any** address in the RRset is blocked (defeats split public/private RRsets), rejects empty resolution, unwraps v4-mapped and v4-compatible IPv6 by prefix rather than the obsolete `#ipv4_compat?`, and blocks the transition prefixes (Teredo 2001::/32, 6to4, NAT64) that the predecessor lists missed. Resolution goes through `Resolv::DNS` rather than the generic resolver, so `/etc/hosts` cannot influence it. Consumers pin to one validated IP, closing the validate-then-re-resolve rebinding window.
- **`SafeFetch` redirect handling.** Never lets Net::HTTP auto-follow; each hop is re-validated through the guard under a redirect cap, with a per-call monotonic deadline spanning all hops (slowloris × redirect fan-out).
- **`Auth::OidcHttpPinning`.** Refuses to operate through a forward proxy (which would re-resolve the hostname outside our control) rather than silently degrading, and re-runs per connection, so a Faraday-followed redirect to a new host is re-validated rather than inheriting a stale pin.
- **`AdminNetworkIsolation`.** Fails closed on every axis examined: unreadable config uses a sentinel distinct from "unset" (so a raising `OT.conf` cannot degrade a configured gate to inactive); a configured-but-unenforceable list denies rather than self-disabling; provenance is checked *before* membership, so an attacker-set forwarded host on the allowlist is still denied; the path is normalized with the same `Otto::Utils.normalize_path` the router dispatches on, so `/%63olonel` cannot skip the gates; an unnormalizable path is judged as an admin surface; membership uses the pre-mask `otto.ip_match` closure rather than the privacy-masked `otto.client_ip`; and denials return 404, not 403.
- **`trusted_proxy_mode` accessor (#4087).** Canonicalizes case, warns (rather than silently falling through) on an unrecognized value, and is now the single reader shared by the IP-privacy mount, the admin posture line, and the two rate-limiter hints — so the posture logged cannot diverge from the posture in force. The rate-limiter changes in this window touch only diagnostic hint text, not limiting behavior.
- **Stripe currency migration (`apps/web/billing/lib/currency_migration_service.rb`).** Authorization is correct (`load_organization(..., require_owner: true)`), `past_due?` blocks migration, and the target price is validated against the local catalog. `StripeClient#create` computes one idempotency key *outside* its retry loop (`stripe_client.rb:99-110`) and disables the SDK's own retries, so a network retry cannot double-issue the credit note. A double-refund via application-level retry is prevented structurally: `Stripe::Subscription.cancel` raises on an already-canceled subscription and the refund call sits after it. `issue_prorated_refund` is best-effort by design and the caller reports `refund_failed` with `refund_amount: 0` rather than claiming money moved (`:343-349`) — honest failure reporting.
- **Link-domains pool at secret creation (#4063).** Pool membership comes from operator config (`features.domains.link_domains`), never from user input, and normalization mirrors `default_domain?` on both sides. Unparseable input falls through to the existing unknown-domain rejection. Guests remain pinned to the Host header on branded domains, so #3311's tenant-phishing rule is not reopened.
- **V2 TTL bounds (#4008).** The nil case is handled by `@ttl = ttl.to_i` before the new `safety_max` comparison, the free-tier entitlement gate still fires loudly before clamping, and the anonymous ceiling is unaffected. The `Float::INFINITY` unlimited-plan case is terminated by `MAX_TTL` as intended.
- **`PendingFederatedSubscription` plan resolution (#4043).** Plan id is read from webhook-sourced subscription metadata and validated through `PlanResolver.canonical_plan_id?` before use; planless records are now refused rather than claimed-and-destroyed, so a failed claim can retry instead of silently stranding a paid customer on Free.
- **General sweep.** No `Marshal.load`, unsafe `YAML.load`, `eval` on untrusted input, `system(`/backtick command construction, or SQL string interpolation in any non-spec `.rb` file. No hardcoded credentials introduced anywhere in the 448-commit delta (scanned all non-test `.rb`/`.ts`/`.yaml`/`.env` diffs for assigned literals ≥16 chars). Secret/token comparisons consistently use `Rack::Utils.secure_compare` or `OpenSSL.secure_compare`. Redis read-modify-write sequences in the models and rate limiters are wrapped in Lua (`eval`) or Familia MULTI-backed primitives rather than done in two round trips.
- **Sibling repos.** No security-relevant delta since 2026-08-06: `familia`, `rodauth-oauth`, `rodauth-omniauth`, and `omniauth` have no new commits; `rodauth` has doc typos and a spec arity fix; `rodauth-tools` and `otto` carry dependency bumps plus otto's `via_trusted_proxy` tri-state work (#226/#228), which the onetimesecret side consumes correctly — `AdminNetworkIsolation#host_provenance_trusted?` reads it as `== true`, the grant-only form the tri-state requires.
