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

**Update 2026-10-09.** A second round repeated B1 and B3 in Chromium, Firefox and WebKit and added a corrected cross-site test (a no-preflight form POST and simple fetch, replacing the earlier credentialed fetch whose `TypeError` was mis-read as blocked-before-auth). See [Browser validation round 2](#browser-validation-round-2-chromium-firefox-webkit). In all three engines no replayable Basic cache arose, the cross-site POST reached the server but carried no `Authorization` header and so was evaluated anonymously, and the victim's authenticated receipt list stayed empty. The three-engine coverage removes the "two of three untested" gap for the two cache-population paths and the cross-site shape; it does not close the class, which still depends on the unprompted-challenge invariant and was not exercised against a production edge or a same-site sibling origin.

**Severity is unconfirmed; the initial Medium is withdrawn as an established rating.** It was conditional on reproducing an authenticated browser state change, which did not occur in Chromium or, as of 2026-10-09, in Firefox or WebKit. The concern is not demonstrated. It is also not disproven as a class: the production edge, a same-site sibling origin, and future challenge-selection changes remain untested paths. It remains an open investigation rather than a confirmed vulnerability or an accepted risk.

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

## Browser validation round 2 (Chromium, Firefox, WebKit)

Added 2026-10-09 against baseline `6090151320` (unchanged; no application code
was modified for this round). Real Chromium (build 1243), Firefox (1538) and
WebKit (2336) driven by Playwright 1.62.1 under Node v26.4.0, headless, a fresh
browser context per engine, no custom flags, `ignoreHTTPSErrors`. Target
`https://dev.onetime.dev` through the live Caddy edge to Puma, development
configuration, `MIDDLEWARE_HTTP_ORIGIN` unset (same effective config as the
2026-10-04 round). A throwaway `customer`-role account distinct from the
earlier round was used; per-request headers, bodies and response statuses
were captured from inside the browser, and victim attribution was read from
outside the browser via authenticated `GET /api/v2/receipt/recent`. The
attacker page was served from `http://127.0.0.1:8099`, a distinct host and
therefore cross-site to the target. Each cross-site attempt carried a unique
marker string as its secret value so a created record could be traced to the
exact attempt. Credential values were not recorded.

This round carries a corrected cross-site test. The 2026-10-04 B4 used a
`credentials: 'include'` fetch and reported `TypeError: Failed to fetch`,
read as "blocked by CORS before auth". That conclusion was unsafe: it did not
record the request's content type, and a simple request reaches the server
before its response is hidden. Round 2 replaces it with two no-preflight
shapes — a real `<form>` POST and a `no-cors` `fetch`, both
`application/x-www-form-urlencoded` — and records whether the request was
sent, what headers it carried, and server-side attribution.

| ID | Browser action | Chromium | Firefox | WebKit | What it establishes |
|---|---|---|---|---|---|
| B1 | Embedded-userinfo navigation, then headerless same-origin fetch | headerless `401` | headerless `401` | headerless `401` | No engine populated a replayable Basic cache from embedded userinfo. |
| B3 | Explicit-`Authorization` same-origin fetch (`200`), then headerless same-origin fetch | headerless `401` | headerless `401` | headerless `401` | In no engine does prior intentional Basic use populate a reusable HTTP auth cache (R4C3C-2). |
| X-form | Cross-site `<form>` POST to `/api/v2/secret/conceal` | request sent, **no `Authorization`** | request sent, server `200`, **no `Authorization`** | request sent, **no `Authorization`** | The cross-site POST is NOT blocked before the handler; it reaches the server. It carries no ambient credential in any engine, so it is evaluated anonymously, not as the victim. |
| X-fetch | Cross-site `no-cors` simple `fetch` to the same endpoint | sent, opaque response | sent, opaque response | sent, opaque response | Same shape, same result: sent, credential-free, opaque to the attacker. |
| Attribution | Victim `GET /api/v2/receipt/recent` after all attempts | `count: 0` | `count: 0` | `count: 0` | No forged conceal was attributed to the victim account in any engine. |

Firefox captured response status directly (the cross-site form POST returned
`200`); Chromium and WebKit report opaque cross-origin responses and so show
the request sent without a readable status. In all three engines the recorded
request carried no `Authorization` header, and the victim's authenticated
receipt list stayed empty, so the anonymous `200` is an anonymous conceal, not
a victim-attributed one. The conditional failure scenario's step 1 (a
populated Basic cache) and step 5 (Basic identifying the victim) did not occur
in any tested engine.

Scope limits for round 2: three engines at the versions named, development
baseline with `MIDDLEWARE_HTTP_ORIGIN` unset and the production edge/proxy not
exercised. The same-site sibling-origin case (a hostile page on a subdomain of
the canonical host, which `Sec-Fetch-Site` would report as same-site) was not
exercised: the attacker origin used is cross-site, and a resolvable sibling
subdomain was not available in this environment. The invariant that no surface
returns `WWW-Authenticate: Basic` to an unprompted request remains the
operative block and is spec-guarded, not re-proven here.

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

The Chromium round above covers the prerequisite and cross-site replay for one engine. [Round 2 (2026-10-09)](#browser-validation-round-2-chromium-firefox-webkit) closed items 1 and 2 and the core of item 4's `MIDDLEWARE_HTTP_ORIGIN`-unset path across all three engines. The remaining work is:

1. ~~**Repeat the prerequisite test in Firefox and WebKit.**~~ Done 2026-10-09 (round 2, B1/B3): no reusable HTTP auth cache arose in Chromium, Firefox or WebKit.
2. ~~**Repeat cross-site submission and consequence checks in those engines.**~~ Done 2026-10-09 (round 2, X-form/X-fetch/Attribution) with the corrected no-preflight shape: the cross-site POST reached the server, carried no `Authorization` in any engine, and attributed nothing to the victim. **Still open:** the same-site sibling-origin case (a hostile page on a subdomain of the canonical host), which round 2 did not exercise because no resolvable sibling subdomain was available; `Sec-Fetch-Site` would classify it same-site, so it is not covered by cross-site reasoning.
3. **Guard the invariant.** Confirm no application surface returns `WWW-Authenticate: Basic` to an unprompted (headerless) request. The Chromium block depends on this; a change to challenge selection (for example in `session_failure_code.rb`) reopens the concern and warrants re-running the full round.
   - Regression specs were added 2026-10-04 (parent `c5cb8c9a63`; the files they exercise are byte-identical to the `6090151320` probe baseline). A unit spec (`50b203c49a`, [`session_failure_code_spec.rb`](../../../spec/unit/onetime/middleware/session_failure_code_spec.rb), block `RISK-2026-10-03-4C3C`) drives the real `BasicAuthStrategy#parse_basic_auth_credentials` and asserts a headerless request stashes no challenge scheme while a present-but-malformed header stashes `Basic`; a route-level spec ([`basicauth_fallthrough_spec.rb`](../../../spec/api/v2/basicauth_fallthrough_spec.rb)) asserts a headerless `GET /api/v2/receipt/recent` 401 never carries `WWW-Authenticate: Basic` through the real Otto chain, while a rejected credential does. The unit guard was confirmed by mutation: stashing `SCHEME_BASIC` on the headerless path turned the assertion red (`expected nil, got "Basic"`). These guard the two paths that carry the scheme — the strategy parser and `Helpers#credentialed_failure`, the sole caller of `stash_scheme` — and are not proof that no surface anywhere emits `Basic` to an unprompted request. Note the `basicauth`-only 401 currently carries no challenge at all; an RFC 9110 §15.5.2 cleanup there would naturally choose `Basic` (the applicable scheme for that resource), which reopens this item.
4. **Check controls and production edge.** Compare an empty authentication cache, an authenticated session without a CSRF token, and Origin protection enabled versus disabled; distinguish rejection by the browser, application, and proxy. The Chromium round ran against a development baseline with `MIDDLEWARE_HTTP_ORIGIN` unset; production edge and proxy behavior were not exercised.

Keep raw credential-bearing traces private. Publish sanitized results and their limitations. Determine severity from the authenticated actions actually demonstrated. A negative result must name the browser versions and flows tested rather than claim universal impossibility.

A Chromium browser round was performed on 2026-10-04 (baseline `6090151320`); no application changes were made. Regression specs guarding the step-3 invariant over its two named code paths were added the same day — unit at `50b203c49a`, route-level in the same branch — with no application code changed. A three-engine round (Chromium, Firefox, WebKit) was performed on 2026-10-09 against the same baseline with no application changes; it closed validation items 1 and 2 across all three engines and corrected the 2026-10-04 cross-site test. This audit still does not close or accept the concern: the step-3 invariant must hold, and the production edge and a same-site sibling origin were not exercised.
