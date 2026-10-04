# Security Audit — 2026-10-03: Basic-auth API CSRF exemption

- **Report:** 4c3c
- **Register:** `RISK-2026-10-03-4C3C`
- **Scope:** Whether cached browser HTTP Basic credentials can authorize a cross-site, state-changing `/api/` request despite the absence of an authenticated session.
- **Reported live baseline:** `6090151320`, development environment, full authentication mode, `MIDDLEWARE_HTTP_ORIGIN` unset.
- **Source-review baseline:** `7a9a7d551c42aa54bcd7d58d6ca4388ae9410d08`. The working tree was clean before this documentation change. This is not the reported live baseline; equivalence between them was not verified.
- **Method:** Targeted source inspection and review of an operator-supplied local validation summary. The reported live requests were not independently rerun. No browser test results were supplied or produced for this assessment.

> **Historical record.** This report captures the available evidence, not a security guarantee or acceptance decision. The [active security risk register](../active-risk-register.md) tracks current disposition.

## Conclusion and severity

The sessionless API CSRF-token exemption is confirmed. The reported challenge behavior limits one way a browser could acquire cached Basic credentials: the tested headerless requests do not receive a Basic challenge. It does not establish that browser-cached credentials are impossible or that previously cached credentials cannot be replayed cross-site.

**Severity is unconfirmed.** The initial Medium assessment was conditional on authenticated browser state change. It is not an established severity rating. The browser-CSRF concern is neither demonstrated nor refuted, and remains an open investigation rather than a confirmed vulnerability or an accepted risk.

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

## Conditional failure scenario

1. A browser has valid API credentials in an HTTP authentication cache applicable to the target endpoint.
2. No authenticated session accompanies the attack request.
3. An attacker-controlled page causes an unsafe request that the browser sends with those cached credentials.
4. The endpoint accepts the method and body encoding, and no independent Origin or edge control rejects it.
5. Basic authentication identifies the victim while the sessionless API token exemption permits the request.

The consequence would be an unintended action under the victim's API identity. Secret creation could produce unwanted account-attributed records and resource use. Broader destructive impact has not been established.

Steps 1, 3, and the browser-specific parts of step 4 remain untested. Neither a 200 response nor an anonymous secret record proves this scenario. CSRF alone also does not establish response disclosure, API-key theft, or account takeover.

## Review disposition ledger

| ID | Concern about the original validation summary | Disposition in this audit |
|---|---|---|
| R4C3C-1 | Curl results were presented as a failed browser reproduction. | Corrected: results are reported HTTP observations; browser reproduction remains pending. |
| R4C3C-2 | Lack of a Basic challenge on headerless requests was treated as proof that cached credentials cannot exist. | Corrected: challenge selection limits exposure but does not refute an already-cached-credential scenario. E2 supplies a Basic-challenge path; its browser-cache effects are unknown. |
| R4C3C-3 | A code comment was treated as proof of safety, and future Basic challenges as proof of exploitation. | Corrected: comments express intent. Changing challenge behavior warrants reassessment, but exploitation still requires credential replay and an accepted authenticated action. |

Anonymous cross-origin creation alone is not evidence of victim-identity CSRF. A standalone scripted client intentionally supplying its API key likewise does not demonstrate browser CSRF. Neither observation disposes of the cached-browser-credential question.

The supplied summary attributed challenge hardening to PR #4223. That attribution was not verified and is not used as evidence of implementation provenance or closure.

## Required validation

Use dedicated local test accounts and non-sensitive payloads. Record exact code revision, working-tree changes, effective middleware settings, browser versions, and test commands or automation.

1. **Establish the prerequisite.** In real Chromium, Firefox, and WebKit browsers, test intentional API authentication and applicable credential-bearing navigation/challenge flows. Record whether they actually populate a reusable HTTP authentication cache. Explicitly adding an Authorization header in automation is not evidence of automatic replay.
2. **Separate session and HTTP-auth state.** Verify there is no authenticated session without inadvertently clearing the HTTP authentication cache under test.
3. **Exercise cross-site submission.** From a separate origin, submit a browser-valid request to the candidate endpoint. Record method, content type, Origin, cookie state, and whether Authorization was automatically attached, without publishing credential values. Include same-site cross-origin coverage where applicable.
4. **Verify the consequence.** Establish server-side account attribution and resulting state. Do not count anonymous success as authenticated CSRF.
5. **Check controls.** Compare an empty authentication cache, an authenticated session without a CSRF token, and Origin protection enabled versus disabled. Distinguish rejection by the browser, application, and proxy.

Keep raw credential-bearing traces private. Publish sanitized results and their limitations. Determine severity from the authenticated actions actually demonstrated. A negative result must name the browser versions and flows tested rather than claim universal impossibility.

No application changes, browser tests, or live curl reruns were performed while creating this record. This audit does not close or accept the concern.
