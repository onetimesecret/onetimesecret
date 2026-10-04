# Security Audit — 2026-10-03: Basic-auth API CSRF exemption

- **Report:** 4c3c
- **Register:** `RISK-2026-10-03-4C3C`
- **Scope:** Whether cached browser HTTP Basic credentials can authorize a cross-site, state-changing `/api/` request despite the absence of an authenticated session.
- **Reported live baseline:** `6090151320`, development environment, full authentication mode, `MIDDLEWARE_HTTP_ORIGIN` unset.
- **Source-review baseline:** `7a9a7d551c42aa54bcd7d58d6ca4388ae9410d08`. The working tree was clean before this documentation change. This is `6090151320` plus one commit; that commit touches only `organization_loader.rb`, `organization_context.rb`, and a spec. Every file this audit relies on is byte-identical between the two revs (see "Baseline equivalence").
- **Browser-validation baseline:** `6090151320` (same as the reported live baseline), full authentication mode, `MIDDLEWARE_HTTP_ORIGIN` unset. Both the server and the test runner were at this commit; the test-runner worktree was clean.
- **Method:** Targeted source inspection and review of an operator-supplied local validation summary, **followed by a real-browser round (Chromium only) added 2026-10-04** against the live baseline. The round exercised the credential-cache prerequisite and cross-site replay directly; see "Browser validation (Chromium)". Firefox and WebKit were not tested. Raw, credential-bearing traces are kept in a local, git-ignored file (`security-audit-2026-10-03-browser-evidence.txt`); this record carries sanitized results only.

### Baseline equivalence

The source-review and browser-validation baselines are equivalent for this audit. `6090151320` is a direct ancestor of `7a9a7d551c42aa54bcd7d58d6ca4388ae9410d08`; the single commit between them changes only `lib/onetime/application/organization_loader.rb`, `lib/onetime/logic/organization_context.rb`, and `spec/unit/organization_loader_cache_scope_spec.rb`. The files this audit depends on — `lib/onetime/middleware/registry.rb`, `lib/onetime/application/auth_strategies/basic_auth_strategy.rb`, `lib/onetime/middleware/session_failure_code.rb`, `etc/config.yaml`, and `apps/api/v2/routes.txt` (with `base_secret_action.rb`) — are byte-identical across the two revs. Source observations and browser results therefore describe the same code.

> **Historical record.** This report captures the available evidence, not a security guarantee or acceptance decision. The [active security risk register](../active-risk-register.md) tracks current disposition.

## Conclusion and severity

The sessionless API CSRF-token exemption is confirmed. A Chromium browser round (below) tested the two plausible ways a browser could acquire cached Basic credentials for this host — embedded userinfo, and prior intentional same-origin authenticated use — and neither populated a replayable HTTP authentication cache in Chromium. A cross-site replay to a victim-attributed state change was not reproduced, and account attribution was unchanged. These results narrow but do not universally close the concern: Firefox and WebKit were not tested, and a future surface that returns a `Basic` challenge to an unprompted request would reopen it.

**Severity is unconfirmed; the initial Medium is withdrawn as an established rating.** It was conditional on reproducing an authenticated browser state change, which did not occur in Chromium. The concern is not demonstrated; it is also not disproven as a class, because two of three target browsers remain untested. It remains an open investigation rather than a confirmed vulnerability or an accepted risk.

## Source evidence

The following implementation observations come from source inspection, not browser execution. Links point to repository files; the baseline above identifies the inspected version.

| Component | Observed behavior | Limitation |
|---|---|---|
| [CSRF registry](../../../lib/onetime/middleware/registry.rb), lines 110–113 | For `/api/`, `return true unless session && session['authenticated'] == true` exempts requests without an authenticated session from the token check. | Absence of an authenticated session does not establish absence of another ambient credential. |
| [BasicAuthStrategy](../../../lib/onetime/application/auth_strategies/basic_auth_strategy.rb), lines 32–100 | Validates customer identifier/email and API key, then returns the authenticated customer. It does not set the session's authenticated flag. | Normal web login credentials and API credentials are distinct. Ordinary web login alone does not establish the reported prerequisite. |
| [Middleware configuration](../../../etc/config.yaml), line 514 | `http_origin` is enabled only when `ENV['MIDDLEWARE_HTTP_ORIGIN'] == 'true'`. | The separate Origin check is opt-in here. Production settings and edge controls were not inspected. |
| [SessionFailureCode](../../../lib/onetime/middleware/session_failure_code.rb), methods `annotate` and `challenge` | For qualifying annotated 401 responses, chooses Basic when the stashed scheme is Basic, otherwise Session. Preserves an existing challenge header. | This is not proof that every response path or intermediary can never issue a Basic challenge. |
| [V2 routes](../../../apps/api/v2/routes.txt) and [secret creation logic](../../../apps/api/v2/logic/secrets/base_secret_action.rb) | `POST /api/v2/secret/conceal` accepts Basic or anonymous authentication and creates a secret pair. | It is a candidate state-changing endpoint, not a reproduced browser exploit. Accepted browser submission encoding and account attribution remain to be checked. |

Implementation comments describe the intended design. They are not independent evidence that browser caching or cross-site replay cannot occur.

## Reported live observations

These are transcribed from the supplied curl summary. Exact commands, request bodies, complete headers, raw outputs, and live working-tree cleanliness were not supplied. The local hostname and worktree label are omitted from this public record; no private evidence is linked.

| ID | Request as reported | Reported result | What it establishes |
|---|---|---|---|
| E1 | `POST /api/v2/secret/conceal`, no authentication | 200; no `WWW-Authenticate` | This anonymous-capable route did not challenge this request. |
| E2 | Same POST, incorrect Basic credentials | 401; `www-authenticate: Basic realm="onetimesecret"` | A request carrying explicit credentials can reach a Basic-challenge response. |
| E3 | `GET /api/account`, no authentication | 401; `www-authenticate: Session realm="onetimesecret"` | This headerless request received Session, not Basic. |
| E4 | `POST /api/v2/secret/conceal`, `Origin: evil`, no cookie | 200 | The supplied summary identifies this as anonymous creation. It does not establish a victim-account action or real-browser Origin behavior. |

The summary calls the endpoint a live server. Supporting-service topology, stubs, proxies, and other effective configuration were not documented. These observations do not establish production behavior.

## Browser validation (Chromium)

Added 2026-10-04 against baseline `6090151320`. Real Chromium (build 1243) driven by Playwright 1.62.1 under Node v26.4.0, headless, a fresh browser context per run, no custom flags. Target `https://dev.onetime.dev` (public certificate). A throwaway `customer`-role test account was used; attribution was read before and after from outside the browser via `GET /api/v2/receipt/recent` (`auth=basicauth`). The attacker page was served from a distinct loopback origin (`http://127.0.0.1:7777`), cross-origin to the host. Raw traces, the test identity, and exact scripts are in the local git-ignored evidence file; credential values were never recorded.

| ID | Browser action | Result | What it establishes |
|---|---|---|---|
| B1 | Navigate with embedded userinfo (`https://user:pass@host/api/account`); capture host requests/responses | First (and only) host request carried **no** `Authorization` header; response `401 WWW-Authenticate: Session`; no retry | Chromium does not send embedded-userinfo Basic credentials preemptively, and a non-`Basic` challenge triggers no Basic retry. Nothing is cached. |
| B2 | After B1, same-origin headerless `fetch('/api/v2/receipt/recent', {credentials:'include'})` | `401` (`[AUTH_HEADER_MISSING]`) | No credential was cached by B1. |
| B3 | From a tab on the real origin: an explicit-`Authorization` same-origin fetch (`200`), then a later same-origin **headerless** fetch | Later fetch `401` | An explicit-header fetch does not populate Chromium's HTTP auth cache; this is the direct test of the "prior intentional API use" path (R4C3C-2). |
| B4 | Cross-origin attacker page `fetch(..., {credentials:'include'})` to `POST /api/v2/secret/conceal` | `TypeError: Failed to fetch` (blocked by CORS before auth) | The cross-site credentialed fetch does not reach an authenticated evaluation. |
| B5 | Victim receipt count before vs. after B1–B4 | `0` → `0`, unchanged | No forged conceal was attributed to the test account. |

Scope limits: Chromium only; Firefox and WebKit untested, and their HTTP-auth-cache and preemptive-userinfo behavior can differ. No surface was found that returns a `Basic` challenge to an unprompted (headerless) request — that absence is the operative block and the invariant the concern depends on. Production edge and proxy configuration were not exercised.

## Conditional failure scenario

1. A browser has valid API credentials in an HTTP authentication cache applicable to the target endpoint.
2. No authenticated session accompanies the attack request.
3. An attacker-controlled page causes an unsafe request that the browser sends with those cached credentials.
4. The endpoint accepts the method and body encoding, and no independent Origin or edge control rejects it.
5. Basic authentication identifies the victim while the sessionless API token exemption permits the request.

The consequence would be an unintended action under the victim's API identity. Secret creation could produce unwanted account-attributed records and resource use. Broader destructive impact has not been established.

In Chromium, step 1 (a populated HTTP auth cache) did not arise from either tested path, and step 3 (cross-site send with cached credentials) did not occur; see B1–B5. The scenario is therefore unreproduced in Chromium. It remains untested in Firefox and WebKit, and step 1 could still arise from a browser behavior or a server surface not covered here. Neither a 200 response nor an anonymous secret record proves this scenario. CSRF alone also does not establish response disclosure, API-key theft, or account takeover.

## Review disposition ledger

| ID | Concern about the original validation summary | Disposition in this audit |
|---|---|---|
| R4C3C-1 | Curl results were presented as a failed browser reproduction. | Corrected: results are reported HTTP observations; browser reproduction remains pending. |
| R4C3C-2 | Lack of a Basic challenge on headerless requests was treated as proof that cached credentials cannot exist. | Corrected, then tested: challenge selection limits exposure but does not by itself refute an already-cached-credential scenario. The Chromium round (B1, B3) directly tested the two cache-population paths — embedded userinfo and prior intentional same-origin authed use — and neither populated a replayable cache; E2's Basic-challenge path is reached only by a request that already carried credentials. Untested in Firefox/WebKit. |
| R4C3C-3 | A code comment was treated as proof of safety, and future Basic challenges as proof of exploitation. | Corrected: comments express intent. Changing challenge behavior warrants reassessment, but exploitation still requires credential replay and an accepted authenticated action. |

Anonymous cross-origin creation alone is not evidence of victim-identity CSRF. A standalone scripted client intentionally supplying its API key likewise does not demonstrate browser CSRF. Neither observation disposes of the cached-browser-credential question.

The supplied summary attributed challenge hardening to PR #4223. That attribution was not verified and is not used as evidence of implementation provenance or closure.

## Required validation

Use dedicated local test accounts and non-sensitive payloads. Record exact code revision, working-tree changes, effective middleware settings, browser versions, and test commands or automation.

The Chromium round above covers the prerequisite and cross-site replay for one engine. The remaining work is:

1. **Repeat the prerequisite test in Firefox and WebKit.** Run the B1 (embedded userinfo) and B3 (prior intentional same-origin authed use) flows and record whether either populates a reusable HTTP authentication cache in those engines. Their behavior may differ from Chromium's.
2. **Repeat cross-site submission and consequence checks in those engines.** From a separate origin, submit a browser-valid request to the candidate endpoint; record method, content type, Origin, cookie state, and whether Authorization was automatically attached. Establish server-side account attribution; do not count anonymous success as authenticated CSRF. Include same-site cross-origin coverage where applicable.
3. **Guard the invariant.** Confirm no application surface returns `WWW-Authenticate: Basic` to an unprompted (headerless) request. The Chromium block depends on this; a change to challenge selection (for example in `session_failure_code.rb`) reopens the concern and warrants re-running the full round.
4. **Check controls and production edge.** Compare an empty authentication cache, an authenticated session without a CSRF token, and Origin protection enabled versus disabled; distinguish rejection by the browser, application, and proxy. The Chromium round ran against a development baseline with `MIDDLEWARE_HTTP_ORIGIN` unset; production edge and proxy behavior were not exercised.

Keep raw credential-bearing traces private. Publish sanitized results and their limitations. Determine severity from the authenticated actions actually demonstrated. A negative result must name the browser versions and flows tested rather than claim universal impossibility.

A Chromium browser round was performed on 2026-10-04 (baseline `6090151320`); no application changes were made. This audit does not close or accept the concern: Firefox and WebKit remain untested and the invariant in step 3 must hold.
