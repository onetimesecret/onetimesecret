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
