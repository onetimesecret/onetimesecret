---
# docs/specs/custom-mail-sender/sender-identity-validation-report.md
---


# Sender identity fixes: validation report

Date: 2026-10-16. Status: focused fixes implemented and tested; not blanket production-readiness approval. Revision: 2026-10-16, report review findings R1–R12 reconciled (see the ledger).

Tested state: commit `0e9389a40b` on `feat/domains-resolve-collisions-feedback` (commits `4cdaf69a36` through `0e9389a40b`, based on `01cfb53244`). The commands below ran on that code, except for a whitespace-only alignment change in `collision_sender_preservation.rb` that the commit includes. No live-provider requests were made. This report is execution evidence, not an accepted project guarantee.

References: [design proposal](sender-identity-contracts-design.md), [coverage specification](sender-identity-contracts-test-coverage.md).

## Implemented scope

- Every strategy produces a validated hash with `outcome`, derived `deleted`, nonempty `message`, and `error`. `DeleteSenderDomain` rejects malformed or contradictory results instead of inferring success from a missing error.
- Deletion, confirmed absence, deliberate skip, and failure have distinct operation log outcomes. Existing operation `Result(success, message, error)` remains unchanged.
- Lettermint individual lookups and complete inventories share cursor traversal and entry validation. Individual lookup may stop on a valid page containing the target; absence and bulk inventory require exhaustion. Later-page failures and cursor cycles raise rather than exposing partial inventories.
- SendGrid retains limit/offset pagination and configured deletion-ID overrides. Malformed entries, including a matching domain without a valid numeric ID, raise.
- SMTP2GO retains filtered domain lookup and supported legacy entry shapes, but rejects malformed/rejected evidence. Removal validates the documented acknowledgement; it does not add a post-removal lookup or infer absence from generic errors.
- SES still deletes directly by name; SDK `NotFoundException` means absence. SMTP reports a deliberate skip.
- No lookup result-class hierarchy, retries, reconciliation queue, local rollback, locking changes, or public API schema changes were introduced.

## Provider evidence and limits

### Lettermint

Installed `lettermint` 0.2.0 source: `Resources::Domains#list(page_size: nil, page_cursor: nil, ...)`; `Resources::Base#build_params` maps these to `page[size]` and `page[cursor]`. The SDK documents a default page size of 30 and returns parsed response bodies without transforming pagination metadata. `HttpClient#handle_response` passes an error body to `HttpRequestError#response_body` only when it parsed to a Hash.

The current [official Team API OpenAPI schema](https://lettermint.co/docs/api-reference/team/0.0.1/lettermint-team-openapi.json) independently specifies:

- `GET /domains`: `page[size]` defaults to 30; the response has a required top-level `next_cursor`, string or null. Null terminates. The response has no `meta` cursor object. The operation documents 200, 401, 403, and 429 responses, and no 404.
- `DELETE /domains/{domainId}`: HTTP 200 `MessageResponse`, with a required string `message`.
- `DELETE /domains/{domainId}` 404: the description names error code `RESOURCE_NOT_FOUND`, and the body schema is `anyOf` `ErrorMessage` (a top-level `message` only) or `ApiError` (`error.code` and `error.message`). No example is given.

Only an `ApiError` body whose `error.code` is `RESOURCE_NOT_FOUND`, inside the deletion request's rescue, maps to absence. A 404 with an `ErrorMessage` body, or with no body, remains a failure, because it cannot be told apart from a proxy or route 404. Limit: if Lettermint answers a missing domain in the `ErrorMessage` shape, an identity that is already gone reports `failed`, and API sender-config deletion audits `provider_cleanup: failed`.

An HTTP-level test exercises the installed SDK's actual query encoding. Other adapter tests use SDK-resource doubles. Neither demonstrates live account behavior.

### SendGrid and SES

SendGrid's official [list](https://www.twilio.com/docs/sendgrid/api-reference/domain-authentication/list-all-authenticated-domains) reference documents `limit` and `offset` enumeration, with no stated default or maximum `limit`, and types each entry's `id` as `number`. The [delete](https://www.twilio.com/docs/sendgrid/api-reference/domain-authentication/delete-an-authenticated-domain) reference lists HTTP 204 with no body as its only response; it documents nothing for a missing domain ID. Tests preserve the existing 50-entry short-page termination policy.

Limit: the code accepts only a positive `Integer` ID. JSON integer IDs parse to `Integer`; a non-integral number would be rejected as a malformed entry and fail the lookup.

SES mappings were checked against installed `aws-sdk-sesv2` 1.110.0. Parity tests use the real SDK HTTP/error translation, including empty success responses and typed versus untyped 404 errors. Deployment credential chains were not exercised.

### SMTP2GO

Live developer documentation returned HTTP 403 (a firewall block page). The official published OpenAPI 3.1.0 document titled SMTP2GO API v3.0.2 was recovered from the official documentation page's archived ReadMe `ssr-props`, not from a third-party interpretation.

Evidence: [Common Crawl index record](https://index.commoncrawl.org/CC-MAIN-2025-30-index?url=developers.smtp2go.com/reference/view-sender-domains&output=json), capture 2025-07-08 01:56:45 UTC, WARC record `a2a203ef-9979-490f-9ccd-cb18070e815b`, compressed range `166407985–166468319`; recovered payload SHA-1 matched `CMIMM46HPFMVV2FZBZMKB267INCNXEB2`.

That dated schema specifies:

- `/domain/view` optional domain filter: “(Optional) If provided, will only retrieve records for this domain”. The request body has only `domain` and `subaccount_id`; no pagination mechanism is documented in that operation. This does not independently exclude undocumented server-side caps.
- Response `data.domains` is an array, with nested `domain.fulldomain` holding the full name. The official WordPress client corroborates the envelope: [`WordpressPluginAdmin.php` L408–L414](https://github.com/smtp2go-oss/wordpress-plugin/blob/814614240f963c3830cae360deaf8a6c00023029/smtp2go/WordpressPluginAdmin.php#L408-L414) calls `domain/view` and keeps `data`, and the [validation partial L13–L25](https://github.com/smtp2go-oss/wordpress-plugin/blob/814614240f963c3830cae360deaf8a6c00023029/admin/partials/smtp2go-wordpress-plugin-validation-display.php#L13-L25) iterates `domains` and reads `domain->fulldomain`.
- `/domain/remove` HTTP 200 is described as “Sender domain removed”; its example is `{"request_id":"...","data":{"domains":[]}}`. It does not define a `success` boolean. Final code validates this acknowledgement without assuming immediate consistency from an extra lookup.
- Missing-domain error semantics are unspecified. Generic 404/not-found text therefore remains failure. Legacy alternate entry shapes remain supported and tested, but were not independently documented by this schema.

The currentness of the archived contract and actual deployment responses remain unverified.

## Final executed commands

The checkout already contained `.test-mode`. All Ruby tests used the lane runner and its isolated services; provider HTTP/SDK boundaries were stubbed. No pending examples were reported by these focused runs.

```sh
tests/lanes/run unit --quiet \
  --only spec/unit/onetime/mail/sender_strategies \
  --only spec/unit/onetime/mail/sender_strategies_spec.rb \
  --only spec/unit/onetime/mail/smtp2go_client_spec.rb \
  --only spec/unit/onetime/operations/delete_sender_domain_spec.rb \
  --only spec/unit/onetime/operations/delete_sender_domain_parity_spec.rb \
  --only spec/unit/onetime/operations/sender_provider_response_parity_spec.rb \
  --only spec/unit/onetime/operations/provision_sender_domain_spec.rb \
  --only spec/unit/onetime/operations/validate_sender_domain_spec.rb \
  --only spec/unit/onetime/operations/sender_identity_lease_spec.rb \
  --only spec/unit/onetime/operations/domains/collision_sender_preservation_spec.rb \
  --only spec/unit/onetime/operations/domains/collision_sender_pagination_regression_spec.rb
```

Result: **625 examples, 0 failures**, seed `55158`. At `897341ee4d` alone the same command gave 604 examples, 0 failures (seed `16060`); the 21 added examples are the R1, R3, and R12 regressions in the ledger.

```sh
tests/lanes/run simple --quiet \
  --only apps/api/domains/spec/integration/simple/domain_sender_config_spec.rb
```

Result: **72 examples, 0 failures**, seed `54881`. Logs also reported missing frontend Vite assets and deliberately unavailable provisioning credentials; no frontend build was validated.

```sh
bundle exec rubocop --force-exclusion \
  lib/onetime/mail/sender_strategies lib/onetime/operations/delete_sender_domain.rb \
  lib/onetime/operations/domains/collision_sender_preservation.rb
git --no-pager diff --check 01cfb53244
```

Result: **8 Ruby files inspected, no offenses**. The whitespace check compares the base commit with the working tree, so it covers the committed spec files that were untracked when the earlier check ran; it passed. This report file was untracked and checked separately for trailing whitespace. The repository RuboCop configuration excludes spec files.

`tests/lanes/run unit --quiet` was attempted before the final SMTP2GO acknowledgement revision and **timed out at 120 seconds**. No complete full-lane result exists for this work, and the run was not repeated. No full simple lane, CI run, production execution, or real-provider cleanup was run.

Regression capture: the expanded SendGrid/SMTP2GO baseline produced 51 failures across 170 examples before those fixes. The Lettermint baseline also failed the new pagination/outcome regressions; its first capture included an invalid test-token fixture, so that capture is not a clean behavioral failure count. No command, seed, or base commit was recorded for these baseline runs, so the counts cannot be reproduced from this report. Obsolete absence-as-deleted and missing-data-as-nil expectations were updated explicitly.

## Coverage reconciliation

Paths below are under `spec/unit/onetime/` unless an API path is named. “Covered” describes the identified examples, not every provider/scenario combination in the proposal. “Partial” means the examples exercise the scenario with the limit shown. “Not covered” means no example asserts the scenario.

| IDs | Status | Evidence | Applicability / limits |
|---|---|---|---|
| L01–L04 | Covered | `mail/sender_strategies/lettermint_lookup_regression_spec.rb`: later target, early target, exhausted absence, empty inventory; SendGrid strategy pagination examples | SES uses direct deletion; SMTP has no inventory. SMTP2GO filtered absence is tested separately. |
| L05–L08 | Covered | Lettermint malformed later-page parameterization and HTTP failures; SendGrid malformed-entry and later-page examples; SMTP2GO malformed lookup examples; HTTP-level `operations/sender_provider_response_parity_spec.rb` | Transport/SDK boundaries are fake; partial inventories are never returned on failure. |
| L09 | Covered | Lettermint cursor-cycle/malformed-cursor examples and collision refusal examples | Cursor-specific; not applicable to SendGrid offset or name-targeted SES/SMTP2GO paths. |
| L10 | Covered | SendGrid generated inventories of 0/49/50/51/1000 entries | Asserts 1/1/2/2/21 requests, including terminal empty pages. |
| L11–L13 | Covered | Supported SMTP2GO shapes; unrelated-domain matching; early-match versus failed full inventory; list 404 versus target deletion 404 examples | SMTP2GO has no documented pagination in the dated schema; undocumented caps remain unknown. |
| L14 | Not covered | Existing first-match behavior retained | Conflicting duplicate provider entries were not independently verified, and no example was added. |
| D01–D02 | Covered | All remote strategy specs and real-adapter `delete_sender_domain_parity_spec.rb`; `sender_provider_response_parity_spec.rb` | SES absence is delete-time, not an artificial list lookup. |
| D03 / D11 | Covered (SES, Lettermint); not applicable (SendGrid, SMTP2GO) | SES typed/untyped not-found; Lettermint structured delete-only not-found and message-only 404 regression; SendGrid/SMTP2GO unproven errors remain failures | Neither SendGrid nor SMTP2GO documents a missing-target response, so no absence mapping was added for them. |
| D04 / D06 / D09 / D12 | Covered | Strategy rejection/malformed acknowledgement/blank-error examples; real operation parity | SendGrid 204 and SES empty success are accepted; Lettermint and SMTP2GO require their documented response shapes. |
| D05 | Partial | Transport failures in strategy/parity examples, including SES HTTP timeout | Not an exhaustive before/after-dispatch matrix for each provider; no remote-state guarantee after timeout. |
| D07–D08 | Partial | Invalid addresses and missing configured credentials in strategy/operation examples | SES environment/instance-profile credential-chain deployment behavior not exercised. |
| D10 | Covered | `mail/sender_strategies/smtp_sender_strategy_spec.rb` and operation SMTP examples | Deliberate skip, no remote identity request. |
| O01–O04 | Covered (O01 partial) | Both real-strategy operation parity files; failed/absent/deleted log assertions | Real adapter methods run, not final-result stubs. O01 is not the exhaustive D01–D09 cross-product. |
| O05–O07 | Covered | `operations/delete_sender_domain_spec.rb` malformed/contradictory hash, exception, skip cases; `mail/sender_strategies/base_sender_strategy_spec.rb` `#deletion_result` and `#deletion_error_message` examples | Boundary tests intentionally stub returned strategy results to exercise invalid states. |
| O08 | Covered | Lettermint regression: complete preflight followed by fresh later-page cleanup lookup failure | Earlier successful evidence does not mask a fresh failure. |
| C01–C03 | Covered | `operations/domains/collision_sender_preservation_spec.rb` and `collision_sender_pagination_regression_spec.rb` | Real Lettermint pagination; SDK-resource list is stubbed, not `list_domains`. |
| C04–C05 | Covered | Retained unreadable-reference, external-survivor, removal-candidate, cross-group examples | Existing all-reference/refusal policy remains exercised. |
| C06–C08 | Covered | 1000-record/multiple-group request budget, failed-walk retry, datastore-backed dry-run/apply fresh enumeration | Proves request reuse, not a production maintenance-window duration or atomic inventory snapshot. |
| C09–C10 | C09 covered; C10 partial | `apps/api/domains/spec/integration/simple/domain_sender_config_spec.rb`: real SES cleanup denial/deletion/absence | Local removal, normal API response, and failed audit cleanup tested. No API-level SMTP skip example. |
| C11 | Covered | Retained API lease-loss/contention examples and `operations/sender_identity_lease_spec.rb` | Selected lifecycle tests, not every possible concurrent interleaving. |
| C12–C13 | Covered | Lettermint later-page duplicate recovery and failed lookup without another create; SMTP2GO failed duplicate-recovery lookup | Existing create-first provider duplicate recovery remains intentional; no new lookup-first creation policy. |
| C14 | Covered | Exact fixed collision refusal text, nil cause, no SDK response/token/address, no failed cache entry | Does not establish that all adapter logs across the project are scrubbed. |
| C15 | Partial | Adapter verification regressions; selected provision/validate/lease suites; caller inspection | Domain-removal call sites inspected, but a dedicated broader domain-removal suite was not run. |

## Callers and lifecycle

Read-only review traced `DeleteSenderDomain`, `DeleteSenderConfig`, domain removal, collision preservation, and strategy provisioning/verification helper callers. Valid identities/nil-for-confirmed-absence are preserved; failed lookup evidence raises into existing consumer error handling. SendGrid `domain_authentications` now raises instead of returning nil on failed enumeration; collision preflight already wraps provider failures and does not cache them. No remaining discovered caller requires a new result-class migration.

`CollisionSenderPreservation` no longer carries a `:malformed` fallback for a Lettermint entry without an ID: `list_domains` and `domain_entry` raise on such an entry first. Its identity check now guards only the configured SendGrid `domain_id` override, which no listing validates; a blank or non-scalar override refuses with "sendgrid gave no usable identity for the sender domain". `Mailer.provider_credentials('sendgrid')` builds only `api_key`, so installation credentials never supply that override today.

Local-removal and locking production code was not changed. The selected API tests demonstrate that remote failure is recorded after local config removal without rollback or incidental response changes. Collision tests demonstrate that unknown inventory refuses preflight rather than authorizing removal. These observations are narrower than a project-wide persistence/security guarantee.

## Finding ledger and conclusion

The delegated findings were produced in a separate session and their original text is not in the repository. The Finding column summarizes each one from the code changes and the recorded disposition; it is not a quotation.

| ID | Finding | Final disposition |
|---|---|---|
| DEL-01 | SES deletion failures carried no `:error`, so `DeleteSenderDomain` reported them as successful no-ops. | Fixed/retested: SES failures no longer become operation success. |
| DEL-02 | `DeleteSenderDomain` inferred success from a missing `:error`, so malformed or contradictory strategy results passed. | Fixed/retested: malformed or contradictory deletion hashes fail validation. |
| DEL-03 | Absence, skip, and deletion were indistinguishable in results and logs; blank exception messages produced blank errors. | Fixed/retested: absence/skip/deletion separated; blank exceptions get fallback errors. |
| DEL-04 / DEL-06 | SendGrid deletion results lacked the outcome contract; rejected or malformed SMTP2GO lookups read as absence. | Fixed/retested: SendGrid outcome integration and SMTP2GO rejected lookup integration. |
| DEL-05 / EXT-LM-1 | Lettermint deletion lacked the outcome contract, and its lookup read only the first page. | Resolved/retested: Lettermint migrated; final parity and consolidated suites pass. |
| DOC-S2G-1 | SMTP2GO lookup and removal handling rested on no documented response contract. | Resolved for the dated published v3.0.2 contract; final acknowledgement handling follows it. |
| DOC-S2G-1-NF | SMTP2GO missing-domain error semantics are undocumented. | Unspecified provider semantics; conservative failure retained. No verified idempotent missing-target error mapping. |
| DOC-S2G-1-ALT | SMTP2GO alternate entry shapes are undocumented. | Legacy variants preserved/tested; independent provider documentation remains unavailable. |
| DOC-S2G-1-CURRENT | The SMTP2GO contract is an archived capture. | Unresolved evidence limit: current deployment contract not independently observed. |
| Final independent review | Review of the final diff. | No concrete introduced failure scenario found; final SMTP2GO revision reconciled. Review is not proof of absence of defects. |
| R1 | The O05–O07 row cited base result-constructor specs that did not exist. | Fixed: `#deletion_result` and `#deletion_error_message` examples in `base_sender_strategy_spec.rb`. |
| R2 | The coverage table had no status per ID. | Fixed: Status column. |
| R3 | The Lettermint delete 404 is `anyOf` `ErrorMessage`/`ApiError`; only `ApiError` maps to absence. | Recorded as a limit; regression example and code comment pin the failure. Code unchanged by design. |
| R4 | SendGrid types `id` as `number`; the code requires a positive `Integer`. | Recorded as a limit. |
| R6 | The WordPress citation pointed at lines that read only `data`. | Fixed: citation covers the admin call and the partial that reads `domains` and `fulldomain`. |
| R7 | An unnamed skill's `meta.cursor` example was referenced. | Fixed: replaced with the schema fact (no `meta` cursor object). |
| R8 | The earlier whitespace check did not cover untracked spec files. | Fixed: check runs against the base commit. |
| R9 | The baseline failure counts have no command, seed, or base commit. | Recorded; not recoverable. |
| R10 | The tested-state line named an uncommitted tree. | Fixed: names the tested commit. |
| R11 | Ledger IDs had dispositions but no finding text. | Partly fixed: Finding column reconstructed from the code changes; original text unavailable. |
| R12 | `CollisionSenderPreservation` kept an unreachable `:malformed` fallback, and its refusal text described a listing. | Fixed: fallback removed; refusal reworded for the configured override and covered by two examples. |

The focused lookup and cleanup-reporting regressions pass. The full abstraction is not required for those results. This does **not** establish complete coverage of the proposed acceptance matrix or unconditional readiness for large-scale destructive execution. Remaining verification includes a complete broader lane run, CI, current SMTP2GO contract confirmation for installations using it, Lettermint's actual missing-domain 404 body shape, and the partial and uncovered rows above. Proxy trust, tenant authorization, sessions, CSRF, SAML, and unrelated listing paths were not audited by this work.
