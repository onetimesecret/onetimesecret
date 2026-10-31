# Security Resolution Log

This append-only log records verified closure of public security findings. Historical audits retain
the original evidence; each entry here identifies the fix and the baseline used to verify closure.

## 2026-09-09

### RISK-2026-08-13-01 — Resolved

- **Finding:** `RABBITMQ_VERIFY_PEER` failed open when an operator supplied any value other than
  the exact string `true`, disabling AMQPS certificate verification.
- **Source:** [2026-08-13 security audit](../audits/security-audit-2026-08-13.md)
- **Resolution:** `4b27b3c0dc` routes the setting through
  `Onetime::Utils::Strings.strict_bool!` with a default of `true`.
- **Verification:** `tests/lanes/run simple --only spec/unit/onetime/utils/strings_spec.rb
  --only spec/unit/onetime/initializers/setup_rabbitmq_spec.rb` completed with 192 examples and
  0 failures.
- **Closure baseline:** `999967a` on 2026-09-09.

### OBS-2026-08-13-RESTRICT-TO — Resolved

- **Finding:** The 2026-08-13 audit recorded domain `restrict_to` enforcement as known and
  tracked rather than filing it as a rated finding.
- **Source:** [2026-08-13 security audit](../audits/security-audit-2026-08-13.md)
- **Resolution:** `b74175efdb` enforces `restrict_to` across sign-in surfaces; later changes add
  fail-closed handling and coverage.
- **Closure baseline:** `999967a` on 2026-09-09.

## 2026-09-19

### RISK-2026-08-13-02 — Resolved

- **Finding:** A session that had presented a password but not its second factor could read
  `/auth/account`, list and remove active sessions (including every other session of the
  account), and list SSO identities and passkey identifiers, because those routes tested only
  `rodauth.logged_in?`.
- **Source:** [2026-08-13 security audit](../audits/security-audit-2026-08-13.md), finding 2;
  carried as open by the [2026-09-09 audit](../audits/security-audit-2026-09-09.md).
- **Resolution:** `a99a07fb27` (merged to `main` in #4483) gates the `/auth` router on the shared
  customer-session verdict. An `awaiting_mfa` session reaches only the second-factor completion
  routes, logout and `GET /auth/mfa-status`; everything else is answered `401` before any route
  runs. The gate is an allowlist, so routes added later (such as the #4419 re-authentication
  pair) are refused by default.
- **Verification:** `295038d24` adds the every-route example the 2026-09-09 audit asked for to
  `apps/web/auth/spec/integration/full_mfa/customer_session_evaluator_mfa_pending_spec.rb`.
  `tests/lanes/run full-mfa` completed with 17 examples and 0 failures. Details in the
  [2026-09-19 review](../audits/security-audit-2026-09-19.md).
- **Closure baseline:** `295038d24` (`feature/4451-auth-session-consistency`) on 2026-09-19.

### RISK-2026-09-19-01 — Resolved

- **Finding:** In simple authentication mode a request in flight during a logout could write the
  session blob back and re-install the cookie, leaving that browser signed in. The store is
  last-writer-wins and simple mode has no active-session row to make the copy refusable.
- **Source:** [2026-09-19 session-consistency package review](../audits/security-audit-2026-09-19.md),
  finding 1.
- **Resolution:** `c1fe2f8c4` (merged to `main` in #4496). Every path that deletes a session blob first sets a 300-second
  ended-marker (`Onetime::SessionEnded`, key `ended_sid:<HMAC-SHA256 of the id>`, never the id),
  and `Onetime::Session#write_session` looks for it after its own `SET` and takes the copy back
  out, reporting the write as not saved so no cookie is sent. Set-then-delete against
  set-then-check leaves no interleaving in which the copy survives. The review's scope widened
  while fixing it: a single-session revoke (`RevokeForCustomer`, `DeleteSession`) deletes the blob
  and leaves the active-session row, so the same race existed in full mode for revocation; the
  marker is therefore checked in both modes, and the session operations delete blobs through
  `Store.destroy_blob` only.
- **Verification:** `spec/integration/simple/logout_write_back_spec.rb` holds a real request open
  across `GET /logout` and across a colonel revoke, so the late write goes through
  `write_session` itself. With the check disabled 3 of its 4 examples fail (the blob is back and
  the old cookie answers `200`). `tests/lanes/run simple --only
  spec/integration/simple/logout_write_back_spec.rb` completed with 4 examples and 0 failures;
  `tests/lanes/run full-sqlite --only spec/integration/full/logout_ends_active_session_spec.rb`
  with 6 and 0; `tests/lanes/run unit --only spec/unit/onetime/session/ended_spec.rb` with 15
  and 0.
- **Follow-up, `1fe3d0165` (#4496):** two loose ends of the same mechanism. A cookie naming an id with no
  blob (never issued, expired, or ended) is never adopted: the empty session starts under a
  server-generated id, as stock Rack does, which replaces the ended-marker lookup `c1fe2f8c4` made
  on that branch. And `delete_session` destroys the sid-keyed `session_metadata:<sid>` record, so
  an ended session's id no longer stays readable in a key name until that record's 30-day TTL.
  Both are covered in `try/unit/session_try.rb`.
- **Closure baseline:** `c1fe2f8c4` (`main`, #4496) on 2026-09-20.

### RISK-2026-09-19-03 — Resolved

- **Finding:** Personalized `/api` JSON responses sent no `Cache-Control`.
- **Source:** [2026-09-19 session-consistency package review](../audits/security-audit-2026-09-19.md),
  finding 3.
- **Resolution:** `891cbcd23` (merged to `main` in #4496) mounts `Onetime::Middleware::ApiCachePolicy` in the universal
  middleware stack. Every response under `/api` that set no policy of its own is sent with
  `Cache-Control: private, no-store`: all nine API applications, anonymous responses and Otto's
  own error responses included. A route's own header is never overwritten. This is the `/api`
  part of [#4470](https://github.com/onetimesecret/onetimesecret/issues/4470); that issue's
  inventory of the remaining personalized surfaces stands.
- **Verification:** `tests/lanes/run unit --only
  spec/unit/onetime/middleware/api_cache_policy_spec.rb --only
  spec/unit/onetime/application/middleware_manifest_spec.rb` completed with 63 examples and
  0 failures. The customer-session failure matrix asserts the header on every protected API
  refusal and on the authenticated `200` in both lanes: `tests/lanes/run full-sqlite --only
  spec/integration/full/customer_session_failure_matrix_spec.rb` 61 examples, 0 failures;
  `tests/lanes/run simple --only spec/integration/simple/customer_session_failure_matrix_spec.rb`
  25 examples, 0 failures.
- **Closure baseline:** `891cbcd23` (`main`, #4496) on 2026-09-20.

### RISK-2026-09-19-04 — Resolved

- **Finding:** Dashboard data refreshes counted as session activity, so a tab left on the
  dashboard never reached the inactivity deadline.
- **Source:** [2026-09-19 session-consistency package review](../audits/security-audit-2026-09-19.md),
  finding 4.
- **Resolution:** Server half `26ac8f094` (merged to `main` in #4496): a `GET` or `HEAD` carrying `X-Session-Activity: passive`
  is verified in full and moves no inactivity clock
  ([failure matrix D8a](../../authentication/customer-session-failure-matrix.md)). Client half
  `4f2a16370` (#4496): the API client takes a per-request `passive` option, and its request interceptor is
  the one place that writes the header, on `GET` and `HEAD` only and never as an instance default.
  The receipt lists on `/recent` (`DashboardRecent.vue`) and on the dashboard
  (`RecentSecretsTable.vue`) refresh through `useBackgroundRefresh`, every 5 minutes while the tab
  is visible and when it becomes visible again, and each of those requests is passive. The load on
  arrival stays an ordinary request. A hidden tab sends nothing.
- **Correction to the finding:** the two timers it named sent no request. `DashboardRecent.vue`'s
  timer called a refresh that returned early once the list was loaded, and
  `SecretLinksTable.vue`'s timer incremented a value nothing read. The unmarked background request
  that did run was `RecentSecretsTable.vue`'s tab-visibility refresh, which fires only when the
  tab becomes visible again, so a tab left open and untouched was not being kept alive. The
  resolution makes
  the timers work as the release notes describe and marks every background refresh, so the risk
  does not appear with them.
- **Verification:** `pnpm exec vitest run src/tests/api/passiveRequest.spec.ts
  src/tests/apps/workspace/dashboard/passiveRefresh.spec.ts
  src/tests/composables/useBackgroundRefresh.spec.ts src/tests/stores/receiptListStore.spec.ts`
  completed with 44 passed, 1 skipped, 0 failed. `passiveRequest.spec.ts` asserts the header on
  the real `createApi()` client: present on a passive `GET` and `HEAD`, absent on an ordinary
  request, absent on `POST`, `PUT`, `PATCH` and `DELETE` even when asked for, and absent from the
  instance defaults afterwards. `passiveRefresh.spec.ts` mounts both components with the real
  store and interceptor and asserts the header per trigger: arrival none, timer `passive`,
  visibility `passive`, hidden tab no request, unmounted no request. Removing the option from one
  composable fails two of its examples. The server side is asserted by the failure matrix (D8a)
  in both lanes.
- **Residual:** a proxy that strips unknown request headers turns these refreshes back into
  activity (rollout notes). Full mode's absolute session lifetime still applies.
- **Closure baseline:** `4f2a16370` (`main`, #4496) on 2026-09-20.

## 2026-10-07

### RISK-2026-08-14-M11 — Resolved

- **Finding:** `sqlite3` 2.9.5 use-after-free (`GHSA-mwm8-39rw-8826`).
- **Source:** [2026-08-14 historical risk register](../risk-registers/risk-register-2026-08-14.md), M-11.
- **Resolution:** `Gemfile.lock` locks `sqlite3` 2.9.6 on all nine platform entries, with no 2.9.5
  entry left. The advisory lists affected versions as `>= 1.4.0, <= 2.9.5` and the first patched
  version as `2.9.6`. v0.26.13 still locked 2.9.5; v0.26.14 is the first tag that locks 2.9.6.
  `Gemfile` already allowed it (`~> 2.0`).
- **Verification:** lockfile inspection only, on `main` and `develop`. The installed gem was not
  loaded and no test lane was run; the change is a version pin.
- **Closure baseline:** `7d324f41d` (`main`) on 2026-10-07; first release `v0.26.14`.

## 2026-10-11

### RISK-2026-08-14-M02 — Resolved

- **Finding:** Magic links kept the Rodauth 24-hour column-default deadline on PostgreSQL and
  SQLite instead of the configured 15 minutes, because Rodauth writes key deadlines only when
  `set_deadline_values?` is true (MySQL by default).
- **Source:** [2026-08-14 historical risk register](../risk-registers/risk-register-2026-08-14.md), M-2.
  Tracking: #4689.
- **Resolution:** #4703 (`d69d7c80` on `main`). `email_auth_key_insert_hash`
  (`apps/web/auth/config/features/email_auth.rb`) writes the deadline as
  `Sequel.date_add(CURRENT_TIMESTAMP, minutes: 15)`; `set_deadline_values?` stays off, so reset
  and lockout keys are unchanged. A resend inside the window reuses the existing key and does not
  extend its deadline.
- **Verification:** CI on the PR head `ef7f16ca` passed, including `T2 · Ruby Unit Tests`, which
  runs the SQLite examples (`apps/web/auth/spec/config/features/email_auth_deadline_spec.rb`), and
  `T3 · Ruby Auth Configuration (PG agnostic, billing: off)`, the lane named in the run line of the
  PostgreSQL copy (`apps/web/auth/spec/integration/full/email_auth_deadline_on_postgres_spec.rb`,
  shared examples in `apps/web/auth/spec/support/shared_examples/email_auth_deadline_examples.rb`).
  The examples pin issue time + 15 minutes, refusal after 15 minutes, and a resend that keeps the
  original key and deadline. The override and both specs are present at the closure baseline. No
  lane was re-run for this entry.
- **Closure baseline:** `c27d903e` (`main`) on 2026-10-11.

### RISK-2026-10-10-03 — Resolved

- **Finding:** Tenant SSO allowlist entries and asserted addresses were compared byte for byte, so
  the Unicode and A-label forms of one IDN domain denied each other (fail-closed: lost sign-ins).
- **Source:** [2026-10-10 G3 review](../audits/security-audit-2026-10-10.md) S7, probe P5.
  Tracking: #4736.
- **Resolution:** #4751 (`2fe5207f` on `main`), action R4. `SsoConfig#matching_allowed_domain`
  (`lib/onetime/models/custom_domain/sso_config.rb`) tries an exact match first, then compares by
  `AsciiHostname.comparison_key` (`lib/onetime/domain_validation/ascii_hostname.rb`), which
  accepts a Unicode name's A-label only when it decodes back to the name's own NFC lower-case
  spelling. A sign-in admitted only because the forms differed logs
  `omniauth_tenant_domain_idn_match` with `reason: :idn_form_differed`. Entries stay stored as
  typed.
- **Verification:** CI on the PR head `9d6c819c` passed, including `T2 · Ruby Unit Tests` and
  `T3 · Ruby Integration (Full, SQLite, billing: off)`, which carry
  `spec/unit/onetime/domain_validation/ascii_hostname_spec.rb`,
  `apps/web/auth/spec/unit/domain_sso_config_spec.rb` and
  `apps/web/auth/spec/integration/full/callback_validation_spec.rb`. No lane was re-run for this
  entry.
- **Residual:** `SignupConfig#allowed_signup_domains` and the global `allowed_signup_domains`
  still compare byte for byte on the account-creation path; #4751 left them out of scope.
- **Closure baseline:** `c27d903e` (`main`) on 2026-10-11.

## 2026-10-30

T󠄁h󠄁e󠄁 t󠄁w󠄁o󠄁 e󠄁n󠄁t󠄁r󠄁i󠄁e󠄁s󠄁 b󠄁e󠄁l󠄁o󠄁w󠄁 u󠄁s󠄁e󠄁 c󠄁o󠄁d󠄁e󠄁 b󠄁a󠄁s󠄁e󠄁l󠄁i󠄁n󠄁e󠄁 `f42fdedc54afcb5973460358c65e3aef363dd5cd`
o󠄁n󠄁 `main` a󠄁n󠄁d󠄁 [C󠄁I󠄁 r󠄁u󠄁n󠄁 4󠄁1󠄁1󠄁6󠄁7󠄁6󠄁9󠄁0󠄁9󠄁7󠄁0󠄁](https://github.com/onetimesecret/onetimesecret/actions/runs/41167690970).󠄁
T󠄁h󠄁e󠄁 r󠄁u󠄁n󠄁 r󠄁e󠄁p󠄁o󠄁r󠄁t󠄁s󠄁 `success` f󠄁o󠄁r󠄁 `ci-verdict` a󠄁n󠄁d󠄁 e󠄁a󠄁c󠄁h󠄁 v󠄁a󠄁l󠄁i󠄁d󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 l󠄁a󠄁n󠄁e󠄁 l󠄁i󠄁n󠄁k󠄁e󠄁d󠄁 b󠄁e󠄁l󠄁o󠄁w󠄁.󠄁
N󠄁o󠄁 t󠄁e󠄁s󠄁t󠄁 l󠄁a󠄁n󠄁e󠄁 w󠄁a󠄁s󠄁 r󠄁e󠄁-󠄁r󠄁u󠄁n󠄁 l󠄁o󠄁c󠄁a󠄁l󠄁l󠄁y󠄁 f󠄁o󠄁r󠄁 t󠄁h󠄁e󠄁s󠄁e󠄁 d󠄁o󠄁c󠄁u󠄁m󠄁e󠄁n󠄁t󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 c󠄁h󠄁a󠄁n󠄁g󠄁e󠄁s󠄁.󠄁

### RISK-2026-08-14-COOKIE-TOSSING — Resolved

- **F󠄁i󠄁n󠄁d󠄁i󠄁n󠄁g󠄁:󠄁** D󠄁u󠄁p󠄁l󠄁i󠄁c󠄁a󠄁t󠄁e󠄁 s󠄁e󠄁s󠄁s󠄁i󠄁o󠄁n󠄁 c󠄁o󠄁o󠄁k󠄁i󠄁e󠄁s󠄁 w󠄁e󠄁r󠄁e󠄁 n󠄁o󠄁t󠄁 r󠄁e󠄁f󠄁u󠄁s󠄁e󠄁d󠄁,󠄁 a󠄁n󠄁d󠄁 s󠄁i󠄁m󠄁p󠄁l󠄁e󠄁-󠄁m󠄁o󠄁d󠄁e󠄁 p󠄁a󠄁s󠄁s󠄁w󠄁o󠄁r󠄁d󠄁 s󠄁i󠄁g󠄁n󠄁-󠄁i󠄁n󠄁
  r󠄁e󠄁u󠄁s󠄁e󠄁d󠄁 t󠄁h󠄁e󠄁 s󠄁e󠄁s󠄁s󠄁i󠄁o󠄁n󠄁 I󠄁D󠄁 p󠄁r󠄁e󠄁s󠄁e󠄁n󠄁t󠄁e󠄁d󠄁 b󠄁e󠄁f󠄁o󠄁r󠄁e󠄁 a󠄁u󠄁t󠄁h󠄁e󠄁n󠄁t󠄁i󠄁c󠄁a󠄁t󠄁i󠄁o󠄁n󠄁.󠄁
- **S󠄁o󠄁u󠄁r󠄁c󠄁e󠄁:󠄁** [2󠄁0󠄁2󠄁6󠄁-󠄁0󠄁8󠄁-󠄁1󠄁4󠄁 h󠄁i󠄁s󠄁t󠄁o󠄁r󠄁i󠄁c󠄁a󠄁l󠄁 r󠄁i󠄁s󠄁k󠄁 r󠄁e󠄁g󠄁i󠄁s󠄁t󠄁e󠄁r󠄁](../risk-registers/risk-register-2026-08-14.md).󠄁
- **R󠄁e󠄁s󠄁o󠄁l󠄁u󠄁t󠄁i󠄁o󠄁n󠄁:󠄁** `d5e80277cc` m󠄁o󠄁u󠄁n󠄁t󠄁s󠄁 `Onetime::Middleware::CookieTossing` b󠄁e󠄁f󠄁o󠄁r󠄁e󠄁
  `Onetime::Session`,󠄁 s󠄁o󠄁 a󠄁 d󠄁u󠄁p󠄁l󠄁i󠄁c󠄁a󠄁t󠄁e󠄁-󠄁c󠄁o󠄁o󠄁k󠄁i󠄁e󠄁 r󠄁e󠄁f󠄁u󠄁s󠄁a󠄁l󠄁 l󠄁o󠄁a󠄁d󠄁s󠄁 n󠄁o󠄁 s󠄁e󠄁s󠄁s󠄁i󠄁o󠄁n󠄁 a󠄁n󠄁d󠄁 r󠄁e󠄁t󠄁u󠄁r󠄁n󠄁s󠄁 o󠄁n󠄁l󠄁y󠄁 c󠄁o󠄁o󠄁k󠄁i󠄁e󠄁
  c󠄁l󠄁e󠄁a󠄁r󠄁s󠄁.󠄁 T󠄁h󠄁e󠄁 m󠄁i󠄁d󠄁d󠄁l󠄁e󠄁w󠄁a󠄁r󠄁e󠄁 c󠄁h󠄁e󠄁c󠄁k󠄁s󠄁 t󠄁h󠄁e󠄁 c󠄁o󠄁n󠄁f󠄁i󠄁g󠄁u󠄁r󠄁e󠄁d󠄁 c󠄁o󠄁o󠄁k󠄁i󠄁e󠄁 n󠄁a󠄁m󠄁e󠄁,󠄁 c󠄁l󠄁e󠄁a󠄁r󠄁s󠄁 h󠄁o󠄁s󠄁t󠄁 a󠄁n󠄁d󠄁 p󠄁a󠄁r󠄁e󠄁n󠄁t󠄁-󠄁d󠄁o󠄁m󠄁a󠄁i󠄁n󠄁
  c󠄁o󠄁p󠄁i󠄁e󠄁s󠄁,󠄁 a󠄁n󠄁d󠄁 k󠄁e󠄁e󠄁p󠄁s󠄁 i󠄁t󠄁s󠄁 r󠄁e󠄁f󠄁u󠄁s󠄁a󠄁l󠄁 s󠄁t󠄁a󠄁t󠄁e󠄁 p󠄁e󠄁r󠄁 r󠄁e󠄁q󠄁u󠄁e󠄁s󠄁t󠄁.󠄁
  `59a40e1e08` c󠄁h󠄁a󠄁n󠄁g󠄁e󠄁s󠄁 s󠄁i󠄁m󠄁p󠄁l󠄁e󠄁-󠄁m󠄁o󠄁d󠄁e󠄁 p󠄁a󠄁s󠄁s󠄁w󠄁o󠄁r󠄁d󠄁 s󠄁i󠄁g󠄁n󠄁-󠄁i󠄁n󠄁:󠄁 `AuthenticateSession#start_new_session!`
  c󠄁l󠄁e󠄁a󠄁r󠄁s󠄁 t󠄁h󠄁e󠄁 s󠄁e󠄁s󠄁s󠄁i󠄁o󠄁n󠄁,󠄁 c󠄁a󠄁l󠄁l󠄁s󠄁 `Onetime::SessionRotation.rotate!` b󠄁e󠄁f󠄁o󠄁r󠄁e󠄁 w󠄁r󠄁i󠄁t󠄁i󠄁n󠄁g󠄁 i󠄁d󠄁e󠄁n󠄁t󠄁i󠄁t󠄁y󠄁,󠄁 a󠄁n󠄁d󠄁
  r󠄁e󠄁f󠄁u󠄁s󠄁e󠄁s󠄁 s󠄁i󠄁g󠄁n󠄁-󠄁i󠄁n󠄁 w󠄁h󠄁e󠄁n󠄁 r󠄁o󠄁t󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 d󠄁o󠄁e󠄁s󠄁 n󠄁o󠄁t󠄁 c󠄁o󠄁m󠄁p󠄁l󠄁e󠄁t󠄁e󠄁.󠄁 B󠄁o󠄁t󠄁h󠄁 c󠄁h󠄁a󠄁n󠄁g󠄁e󠄁s󠄁 a󠄁r󠄁e󠄁 p󠄁r󠄁e󠄁s󠄁e󠄁n󠄁t󠄁 a󠄁t󠄁 t󠄁h󠄁e󠄁 b󠄁a󠄁s󠄁e󠄁l󠄁i󠄁n󠄁e󠄁.󠄁
- **V󠄁e󠄁r󠄁i󠄁f󠄁i󠄁c󠄁a󠄁t󠄁i󠄁o󠄁n󠄁:󠄁** T󠄁h󠄁e󠄁 [u󠄁n󠄁i󠄁t󠄁 j󠄁o󠄁b󠄁](https://github.com/onetimesecret/onetimesecret/actions/runs/41167690970/job/124439029352)
  i󠄁n󠄁c󠄁l󠄁u󠄁d󠄁e󠄁s󠄁 `spec/unit/onetime/middleware/cookie_tossing_spec.rb` a󠄁n󠄁d󠄁 t󠄁h󠄁e󠄁 m󠄁i󠄁d󠄁d󠄁l󠄁e󠄁w󠄁a󠄁r󠄁e󠄁 m󠄁a󠄁n󠄁i󠄁f󠄁e󠄁s󠄁t󠄁
  a󠄁s󠄁s󠄁e󠄁r󠄁t󠄁i󠄁o󠄁n󠄁s󠄁.󠄁 T󠄁h󠄁e󠄁 [s󠄁i󠄁m󠄁p󠄁l󠄁e󠄁-󠄁m󠄁o󠄁d󠄁e󠄁 j󠄁o󠄁b󠄁](https://github.com/onetimesecret/onetimesecret/actions/runs/41167690970/job/124439029421)
  i󠄁n󠄁c󠄁l󠄁u󠄁d󠄁e󠄁s󠄁 `spec/integration/simple/login_session_rotation_spec.rb`:󠄁 v󠄁e󠄁r󠄁i󠄁f󠄁i󠄁e󠄁d󠄁 a󠄁n󠄁d󠄁 p󠄁e󠄁n󠄁d󠄁i󠄁n󠄁g󠄁
  a󠄁c󠄁c󠄁o󠄁u󠄁n󠄁t󠄁s󠄁 g󠄁e󠄁t󠄁 a󠄁 n󠄁e󠄁w󠄁 I󠄁D󠄁,󠄁 t󠄁h󠄁e󠄁 o󠄁l󠄁d󠄁 c󠄁o󠄁o󠄁k󠄁i󠄁e󠄁 i󠄁s󠄁 r󠄁e󠄁f󠄁u󠄁s󠄁e󠄁d󠄁,󠄁 p󠄁r󠄁i󠄁o󠄁r󠄁 s󠄁e󠄁s󠄁s󠄁i󠄁o󠄁n󠄁 s󠄁t󠄁a󠄁t󠄁e󠄁 i󠄁s󠄁 r󠄁e󠄁m󠄁o󠄁v󠄁e󠄁d󠄁,󠄁 a󠄁n󠄁d󠄁 a󠄁n󠄁
  i󠄁n󠄁c󠄁o󠄁m󠄁p󠄁l󠄁e󠄁t󠄁e󠄁 r󠄁o󠄁t󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 g󠄁r󠄁a󠄁n󠄁t󠄁s󠄁 n󠄁o󠄁 a󠄁u󠄁t󠄁h󠄁e󠄁n󠄁t󠄁i󠄁c󠄁a󠄁t󠄁e󠄁d󠄁 s󠄁e󠄁s󠄁s󠄁i󠄁o󠄁n󠄁.󠄁 T󠄁h󠄁e󠄁 [f󠄁u󠄁l󠄁l󠄁 S󠄁Q󠄁L󠄁i󠄁t󠄁e󠄁 j󠄁o󠄁b󠄁](https://github.com/onetimesecret/onetimesecret/actions/runs/41167690970/job/124439029430)
  i󠄁n󠄁c󠄁l󠄁u󠄁d󠄁e󠄁s󠄁 `spec/integration/full/customer_session_continuation_baseline_spec.rb`,󠄁 w󠄁h󠄁i󠄁c󠄁h󠄁 c󠄁h󠄁e󠄁c󠄁k󠄁s󠄁
  d󠄁u󠄁p󠄁l󠄁i󠄁c󠄁a󠄁t󠄁e󠄁 c󠄁o󠄁o󠄁k󠄁i󠄁e󠄁s󠄁 i󠄁n󠄁 b󠄁o󠄁t󠄁h󠄁 o󠄁r󠄁d󠄁e󠄁r󠄁s󠄁 a󠄁n󠄁d󠄁 a󠄁 r󠄁e󠄁f󠄁u󠄁s󠄁a󠄁l󠄁 c󠄁o󠄁n󠄁t󠄁a󠄁i󠄁n󠄁i󠄁n󠄁g󠄁 c󠄁l󠄁e󠄁a󠄁r󠄁s󠄁 o󠄁n󠄁l󠄁y󠄁.󠄁
- **C󠄁l󠄁o󠄁s󠄁u󠄁r󠄁e󠄁 b󠄁a󠄁s󠄁e󠄁l󠄁i󠄁n󠄁e󠄁:󠄁** `f42fdedc54afcb5973460358c65e3aef363dd5cd` (󠄁`main`)󠄁 o󠄁n󠄁 2󠄁0󠄁2󠄁6󠄁-󠄁1󠄁0󠄁-󠄁3󠄁0󠄁.󠄁

### RISK-2026-09-19-02 — Resolved

- **F󠄁i󠄁n󠄁d󠄁i󠄁n󠄁g󠄁:󠄁** M󠄁F󠄁A󠄁 c󠄁o󠄁m󠄁p󠄁l󠄁e󠄁t󠄁i󠄁o󠄁n󠄁 k󠄁e󠄁p󠄁t󠄁 t󠄁h󠄁e󠄁 I󠄁D󠄁 i󠄁s󠄁s󠄁u󠄁e󠄁d󠄁 a󠄁t󠄁 t󠄁h󠄁e󠄁 p󠄁a󠄁s󠄁s󠄁w󠄁o󠄁r󠄁d󠄁 s󠄁t󠄁e󠄁p󠄁;󠄁 t󠄁h󠄁e󠄁 w󠄁i󠄁d󠄁e󠄁r󠄁 r󠄁e󠄁v󠄁i󠄁e󠄁w󠄁 a󠄁l󠄁s󠄁o󠄁
  i󠄁d󠄁e󠄁n󠄁t󠄁i󠄁f󠄁i󠄁e󠄁d󠄁 r󠄁e󠄁-󠄁a󠄁u󠄁t󠄁h󠄁e󠄁n󠄁t󠄁i󠄁c󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 p󠄁r󠄁o󠄁o󠄁f󠄁 a󠄁n󠄁d󠄁 f󠄁i󠄁r󠄁s󠄁t󠄁 s󠄁e󠄁c󠄁o󠄁n󠄁d󠄁-󠄁f󠄁a󠄁c󠄁t󠄁o󠄁r󠄁 s󠄁e󠄁t󠄁u󠄁p󠄁 w󠄁i󠄁t󠄁h󠄁o󠄁u󠄁t󠄁 r󠄁e󠄁n󠄁e󠄁w󠄁a󠄁l󠄁,󠄁 a󠄁n󠄁d󠄁 m󠄁i󠄁s󠄁s󠄁i󠄁n󠄁g󠄁
  r󠄁o󠄁t󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 a󠄁s󠄁s󠄁e󠄁r󠄁t󠄁i󠄁o󠄁n󠄁s󠄁 f󠄁o󠄁r󠄁 o󠄁t󠄁h󠄁e󠄁r󠄁 s󠄁i󠄁g󠄁n󠄁-󠄁i󠄁n󠄁 p󠄁a󠄁t󠄁h󠄁s󠄁.󠄁
- **S󠄁o󠄁u󠄁r󠄁c󠄁e󠄁:󠄁** [2󠄁0󠄁2󠄁6󠄁-󠄁0󠄁9󠄁-󠄁1󠄁9󠄁 s󠄁e󠄁s󠄁s󠄁i󠄁o󠄁n󠄁-󠄁c󠄁o󠄁n󠄁s󠄁i󠄁s󠄁t󠄁e󠄁n󠄁c󠄁y󠄁 r󠄁e󠄁v󠄁i󠄁e󠄁w󠄁](../audits/security-audit-2026-09-19.md),󠄁 f󠄁i󠄁n󠄁d󠄁i󠄁n󠄁g󠄁 2󠄁.󠄁
- **R󠄁e󠄁s󠄁o󠄁l󠄁u󠄁t󠄁i󠄁o󠄁n󠄁:󠄁** `64b2c23f23` a󠄁d󠄁d󠄁s󠄁 M󠄁F󠄁A󠄁-󠄁c󠄁o󠄁m󠄁p󠄁l󠄁e󠄁t󠄁i󠄁o󠄁n󠄁 r󠄁o󠄁t󠄁a󠄁t󠄁i󠄁o󠄁n󠄁;󠄁 `0e812e2279` r󠄁e󠄁f󠄁u󠄁s󠄁e󠄁s󠄁 c󠄁o󠄁m󠄁p󠄁l󠄁e󠄁t󠄁i󠄁o󠄁n󠄁 w󠄁h󠄁e󠄁n󠄁
  t󠄁h󠄁e󠄁 o󠄁l󠄁d󠄁 I󠄁D󠄁 c󠄁a󠄁n󠄁n󠄁o󠄁t󠄁 b󠄁e󠄁 e󠄁n󠄁d󠄁e󠄁d󠄁.󠄁 `01fccc49dc`,󠄁 `645e149610` a󠄁n󠄁d󠄁 `54e32e56c3` a󠄁d󠄁d󠄁 r󠄁o󠄁t󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 b󠄁e󠄁f󠄁o󠄁r󠄁e󠄁
  c󠄁o󠄁l󠄁o󠄁n󠄁e󠄁l󠄁 e󠄁l󠄁e󠄁v󠄁a󠄁t󠄁i󠄁o󠄁n󠄁,󠄁 r󠄁e󠄁-󠄁a󠄁u󠄁t󠄁h󠄁e󠄁n󠄁t󠄁i󠄁c󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 p󠄁r󠄁o󠄁o󠄁f󠄁 a󠄁n󠄁d󠄁 f󠄁i󠄁r󠄁s󠄁t󠄁 s󠄁e󠄁c󠄁o󠄁n󠄁d󠄁-󠄁f󠄁a󠄁c󠄁t󠄁o󠄁r󠄁 s󠄁e󠄁t󠄁u󠄁p󠄁 r󠄁e󠄁s󠄁p󠄁e󠄁c󠄁t󠄁i󠄁v󠄁e󠄁l󠄁y󠄁.󠄁
  `4b406aac63` a󠄁n󠄁d󠄁 `ce47edc1a9` a󠄁d󠄁d󠄁 a󠄁s󠄁s󠄁e󠄁r󠄁t󠄁i󠄁o󠄁n󠄁s󠄁 f󠄁o󠄁r󠄁 t󠄁h󠄁e󠄁 r󠄁e󠄁m󠄁a󠄁i󠄁n󠄁i󠄁n󠄁g󠄁 s󠄁i󠄁g󠄁n󠄁-󠄁i󠄁n󠄁 p󠄁a󠄁t󠄁h󠄁s󠄁.󠄁
  T󠄁h󠄁e󠄁 i󠄁m󠄁p󠄁l󠄁e󠄁m󠄁e󠄁n󠄁t󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 a󠄁n󠄁d󠄁 p󠄁e󠄁r󠄁-󠄁p󠄁a󠄁t󠄁h󠄁 i󠄁n󠄁v󠄁e󠄁n󠄁t󠄁o󠄁r󠄁y󠄁 i󠄁n󠄁 `lib/onetime/session/rotation.rb` a󠄁r󠄁e󠄁 p󠄁r󠄁e󠄁s󠄁e󠄁n󠄁t󠄁
  a󠄁t󠄁 t󠄁h󠄁e󠄁 b󠄁a󠄁s󠄁e󠄁l󠄁i󠄁n󠄁e󠄁.󠄁 I󠄁m󠄁p󠄁e󠄁r󠄁s󠄁o󠄁n󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 s󠄁t󠄁a󠄁r󠄁t󠄁/󠄁s󠄁t󠄁o󠄁p󠄁 i󠄁n󠄁t󠄁e󠄁n󠄁t󠄁i󠄁o󠄁n󠄁a󠄁l󠄁l󠄁y󠄁 k󠄁e󠄁e󠄁p󠄁 t󠄁h󠄁e󠄁 s󠄁a󠄁m󠄁e󠄁 I󠄁D󠄁;󠄁 `61f4e7f639` a󠄁d󠄁d󠄁s󠄁
  t󠄁h󠄁e󠄁 c󠄁o󠄁r󠄁r󠄁e󠄁s󠄁p󠄁o󠄁n󠄁d󠄁i󠄁n󠄁g󠄁 r󠄁e󠄁a󠄁l󠄁-󠄁r󠄁o󠄁u󠄁t󠄁e󠄁 a󠄁s󠄁s󠄁e󠄁r󠄁t󠄁i󠄁o󠄁n󠄁s󠄁.󠄁 O󠄁r󠄁g󠄁a󠄁n󠄁i󠄁z󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 s󠄁w󠄁i󠄁t󠄁c󠄁h󠄁i󠄁n󠄁g󠄁 c󠄁h󠄁a󠄁n󠄁g󠄁e󠄁s󠄁 t󠄁h󠄁e󠄁 a󠄁c󠄁t󠄁i󠄁v󠄁e󠄁
  o󠄁r󠄁g󠄁a󠄁n󠄁i󠄁z󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 r󠄁a󠄁t󠄁h󠄁e󠄁r󠄁 t󠄁h󠄁a󠄁n󠄁 t󠄁h󠄁e󠄁 a󠄁u󠄁t󠄁h󠄁e󠄁n󠄁t󠄁i󠄁c󠄁a󠄁t󠄁e󠄁d󠄁 i󠄁d󠄁e󠄁n󠄁t󠄁i󠄁t󠄁y󠄁.󠄁
- **V󠄁e󠄁r󠄁i󠄁f󠄁i󠄁c󠄁a󠄁t󠄁i󠄁o󠄁n󠄁:󠄁** T󠄁h󠄁e󠄁 [M󠄁F󠄁A󠄁 j󠄁o󠄁b󠄁](https://github.com/onetimesecret/onetimesecret/actions/runs/41167690970/job/124439029406)
  i󠄁n󠄁c󠄁l󠄁u󠄁d󠄁e󠄁s󠄁 M󠄁F󠄁A󠄁 c󠄁o󠄁m󠄁p󠄁l󠄁e󠄁t󠄁i󠄁o󠄁n󠄁,󠄁 f󠄁a󠄁c󠄁t󠄁o󠄁r󠄁 s󠄁e󠄁t󠄁u󠄁p󠄁,󠄁 r󠄁e󠄁-󠄁a󠄁u󠄁t󠄁h󠄁e󠄁n󠄁t󠄁i󠄁c󠄁a󠄁t󠄁i󠄁o󠄁n󠄁,󠄁 m󠄁a󠄁g󠄁i󠄁c󠄁-󠄁l󠄁i󠄁n󠄁k󠄁 a󠄁n󠄁d󠄁 p󠄁a󠄁s󠄁s󠄁k󠄁e󠄁y󠄁 r󠄁o󠄁t󠄁a󠄁t󠄁i󠄁o󠄁n󠄁
  s󠄁p󠄁e󠄁c󠄁s󠄁.󠄁 T󠄁h󠄁e󠄁 f󠄁u󠄁l󠄁l󠄁 S󠄁Q󠄁L󠄁i󠄁t󠄁e󠄁 j󠄁o󠄁b󠄁 l󠄁i󠄁n󠄁k󠄁e󠄁d󠄁 a󠄁b󠄁o󠄁v󠄁e󠄁 i󠄁n󠄁c󠄁l󠄁u󠄁d󠄁e󠄁s󠄁 O󠄁I󠄁D󠄁C󠄁 c󠄁a󠄁l󠄁l󠄁b󠄁a󠄁c󠄁k󠄁s󠄁,󠄁 v󠄁e󠄁r󠄁i󠄁f󠄁i󠄁c󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 a󠄁n󠄁d󠄁 i󠄁n󠄁v󠄁i󠄁t󠄁e󠄁
  a󠄁u󠄁t󠄁o󠄁l󠄁o󠄁g󠄁i󠄁n󠄁,󠄁 S󠄁S󠄁O󠄁 l󠄁i󠄁n󠄁k󠄁i󠄁n󠄁g󠄁/󠄁C󠄁o󠄁n󠄁n󠄁e󠄁c󠄁t󠄁,󠄁 i󠄁m󠄁p󠄁e󠄁r󠄁s󠄁o󠄁n󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 a󠄁n󠄁d󠄁 f󠄁u󠄁l󠄁l󠄁-󠄁m󠄁o󠄁d󠄁e󠄁 e󠄁l󠄁e󠄁v󠄁a󠄁t󠄁i󠄁o󠄁n󠄁/󠄁p󠄁a󠄁s󠄁s󠄁w󠄁o󠄁r󠄁d󠄁-󠄁c󠄁h󠄁a󠄁n󠄁g󠄁e󠄁 s󠄁p󠄁e󠄁c󠄁s󠄁;󠄁
  t󠄁h󠄁e󠄁 s󠄁i󠄁m󠄁p󠄁l󠄁e󠄁-󠄁m󠄁o󠄁d󠄁e󠄁 j󠄁o󠄁b󠄁 i󠄁n󠄁c󠄁l󠄁u󠄁d󠄁e󠄁s󠄁 s󠄁i󠄁m󠄁p󠄁l󠄁e󠄁-󠄁m󠄁o󠄁d󠄁e󠄁 e󠄁l󠄁e󠄁v󠄁a󠄁t󠄁i󠄁o󠄁n󠄁/󠄁p󠄁a󠄁s󠄁s󠄁w󠄁o󠄁r󠄁d󠄁-󠄁c󠄁h󠄁a󠄁n󠄁g󠄁e󠄁 s󠄁p󠄁e󠄁c󠄁s󠄁.󠄁
  T󠄁h󠄁e󠄁 [p󠄁l󠄁a󠄁t󠄁f󠄁o󠄁r󠄁m󠄁-󠄁S󠄁A󠄁M󠄁L󠄁 j󠄁o󠄁b󠄁](https://github.com/onetimesecret/onetimesecret/actions/runs/41167690970/job/124439029355)
  i󠄁n󠄁c󠄁l󠄁u󠄁d󠄁e󠄁s󠄁 p󠄁l󠄁a󠄁t󠄁f󠄁o󠄁r󠄁m󠄁 c󠄁a󠄁l󠄁l󠄁b󠄁a󠄁c󠄁k󠄁 r󠄁o󠄁t󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 a󠄁s󠄁s󠄁e󠄁r󠄁t󠄁i󠄁o󠄁n󠄁s󠄁.󠄁 A󠄁l󠄁l󠄁 f󠄁o󠄁u󠄁r󠄁 j󠄁o󠄁b󠄁s󠄁 r󠄁e󠄁p󠄁o󠄁r󠄁t󠄁 `success`.󠄁
- **S󠄁e󠄁p󠄁a󠄁r󠄁a󠄁t󠄁e󠄁 o󠄁p󠄁e󠄁n󠄁 f󠄁o󠄁l󠄁l󠄁o󠄁w󠄁-󠄁u󠄁p󠄁s󠄁:󠄁** [#󠄁4󠄁7󠄁0󠄁6󠄁](https://github.com/onetimesecret/onetimesecret/issues/4706)
  t󠄁r󠄁a󠄁c󠄁k󠄁s󠄁 e󠄁x󠄁i󠄁s󠄁t󠄁i󠄁n󠄁g󠄁 s󠄁e󠄁s󠄁s󠄁i󠄁o󠄁n󠄁s󠄁 r󠄁e󠄁c󠄁e󠄁i󠄁v󠄁i󠄁n󠄁g󠄁 a󠄁 r󠄁o󠄁l󠄁e󠄁 g󠄁r󠄁a󠄁n󠄁t󠄁 w󠄁i󠄁t󠄁h󠄁o󠄁u󠄁t󠄁 a󠄁 n󠄁e󠄁w󠄁 s󠄁i󠄁g󠄁n󠄁-󠄁i󠄁n󠄁;󠄁
  [#󠄁4󠄁7󠄁0󠄁7󠄁](https://github.com/onetimesecret/onetimesecret/issues/4707) t󠄁r󠄁a󠄁c󠄁k󠄁s󠄁 u󠄁s󠄁e󠄁r󠄁-󠄁m󠄁e󠄁n󠄁u󠄁 s󠄁i󠄁g󠄁n󠄁-󠄁o󠄁u󠄁t󠄁
  b󠄁e󠄁i󠄁n󠄁g󠄁 r󠄁e󠄁f󠄁u󠄁s󠄁e󠄁d󠄁 d󠄁u󠄁r󠄁i󠄁n󠄁g󠄁 i󠄁m󠄁p󠄁e󠄁r󠄁s󠄁o󠄁n󠄁a󠄁t󠄁i󠄁o󠄁n󠄁.󠄁 B󠄁o󠄁t󠄁h󠄁 i󠄁s󠄁s󠄁u󠄁e󠄁s󠄁 r󠄁e󠄁m󠄁a󠄁i󠄁n󠄁 o󠄁p󠄁e󠄁n󠄁.󠄁 T󠄁h󠄁i󠄁s󠄁 c󠄁l󠄁o󠄁s󠄁u󠄁r󠄁e󠄁 n󠄁e󠄁i󠄁t󠄁h󠄁e󠄁r󠄁 r󠄁e󠄁s󠄁o󠄁l󠄁v󠄁e󠄁s󠄁
  t󠄁h󠄁o󠄁s󠄁e󠄁 b󠄁e󠄁h󠄁a󠄁v󠄁i󠄁o󠄁r󠄁s󠄁 n󠄁o󠄁r󠄁 r󠄁e󠄁c󠄁o󠄁r󠄁d󠄁s󠄁 a󠄁n󠄁 a󠄁c󠄁c󠄁e󠄁p󠄁t󠄁a󠄁n󠄁c󠄁e󠄁 d󠄁e󠄁c󠄁i󠄁s󠄁i󠄁o󠄁n󠄁 f󠄁o󠄁r󠄁 t󠄁h󠄁e󠄁m󠄁.󠄁
- **C󠄁l󠄁o󠄁s󠄁u󠄁r󠄁e󠄁 b󠄁a󠄁s󠄁e󠄁l󠄁i󠄁n󠄁e󠄁:󠄁** `f42fdedc54afcb5973460358c65e3aef363dd5cd` (󠄁`main`)󠄁 o󠄁n󠄁 2󠄁0󠄁2󠄁6󠄁-󠄁1󠄁0󠄁-󠄁3󠄁0󠄁.󠄁
