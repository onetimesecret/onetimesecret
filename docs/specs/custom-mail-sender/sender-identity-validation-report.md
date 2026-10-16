---
# docs/specs/custom-mail-sender/sender-identity-validation-report.md
---


# Sender identity fixes: validation report

Date: 2026-10-16. Status: focused fixes implemented and tested; not blanket production-readiness approval.

Tested state: uncommitted working tree based on `01cfb53244d0420f2bf436ecd6958da9cc9e0a37`. The final commands below ran after the last production-code change. No commits or live-provider requests were made. This report is execution evidence, not an accepted project guarantee.

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

Installed `lettermint` 0.2.0 source: `Resources::Domains#list(page_size: nil, page_cursor: nil, ...)`; `Resources::Base#build_params` maps these to `page[size]` and `page[cursor]`. The SDK documents a default page size of 30 and returns parsed response bodies without transforming pagination metadata.

The current [official Team API OpenAPI schema](https://lettermint.co/docs/api-reference/team/0.0.1/lettermint-team-openapi.json) independently specifies:

- `GET /domains`: default `page[size]` 30; top-level `next_cursor`, string or null. Null terminates. The skill's `meta.cursor` example is not used.
- `DELETE /domains/{domainId}`: HTTP 200 `MessageResponse`, with a required string `message`.
- Target deletion 404 documents `RESOURCE_NOT_FOUND`. Only that structured error, inside the deletion request's rescue, maps to absence. An unclassified/message-only 404 remains a failure.

An HTTP-level test exercises the installed SDK's actual query encoding. Other adapter tests use SDK-resource doubles. Neither demonstrates live account behavior.

### SendGrid and SES

SendGrid's official [list](https://www.twilio.com/docs/sendgrid/api-reference/domain-authentication/list-all-authenticated-domains) and [delete](https://www.twilio.com/docs/sendgrid/api-reference/domain-authentication/delete-an-authenticated-domain) references support limit/offset enumeration, numeric IDs, and empty HTTP 204 deletion success. Tests preserve the existing 50-entry short-page termination policy.

SES mappings were checked against installed `aws-sdk-sesv2` 1.110.0. Parity tests use the real SDK HTTP/error translation, including empty success responses and typed versus untyped 404 errors. Deployment credential chains were not exercised.

### SMTP2GO

Live developer documentation returned HTTP 403. The official published OpenAPI 3.1 document titled SMTP2GO API v3.0.2 was recovered from the official documentation page's archived ReadMe `ssr-props`, not from a third-party interpretation.

Evidence: [Common Crawl index record](https://index.commoncrawl.org/CC-MAIN-2025-30-index?url=developers.smtp2go.com/reference/view-sender-domains&output=json), capture 2025-07-08 01:56:45 UTC, WARC record `a2a203ef-9979-490f-9ccd-cb18070e815b`, compressed range `166407985–166468319`; recovered payload SHA-1 matched `CMIMM46HPFMVV2FZBZMKB267INCNXEB2`.

That dated schema specifies:

- `/domain/view` optional domain filter: “(Optional) If provided, will only retrieve records for this domain”. No pagination mechanism is documented in that operation. This does not independently exclude undocumented server-side caps.
- Response `data.domains` is an array, with nested `domain.fulldomain` holding the full name. The official [WordPress client](https://github.com/smtp2go-oss/wordpress-plugin/blob/814614240f963c3830cae360deaf8a6c00023029/smtp2go/WordpressPluginAdmin.php#L411-L419) corroborates the envelope.
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

Result: **604 examples, 0 failures**, seed `42670`.

```sh
tests/lanes/run simple --quiet \
  --only apps/api/domains/spec/integration/simple/domain_sender_config_spec.rb
```

Result: **72 examples, 0 failures**, seed `18554`. Logs also reported missing frontend Vite assets and deliberately unavailable provisioning credentials; no frontend build was validated.

```sh
bundle exec rubocop --force-exclusion \
  lib/onetime/mail/sender_strategies lib/onetime/operations/delete_sender_domain.rb
git --no-pager diff --check
```

Result: **7 Ruby files inspected, no offenses**; whitespace check passed.

`tests/lanes/run unit --quiet` was attempted before the final SMTP2GO acknowledgement revision and **timed out at 120 seconds**. No complete full-lane result is claimed; it was not automatically rerun. No full simple lane, production execution, or real-provider cleanup was run.

Regression capture: the expanded SendGrid/SMTP2GO baseline produced 51 failures across 170 examples before those fixes. The Lettermint baseline also failed the new pagination/outcome regressions; its first capture included an invalid test-token fixture, so that capture is not a clean behavioral failure count. Obsolete absence-as-deleted and missing-data-as-nil expectations were updated explicitly.

## Coverage reconciliation

Paths below are under `spec/unit/onetime/` unless an API path is named. “Covered” describes the identified examples, not every provider/scenario combination in the proposal.

| IDs | Evidence | Applicability / limits |
|---|---|---|
| L01–L04 | `mail/sender_strategies/lettermint_lookup_regression_spec.rb`: later target, early target, exhausted absence, empty inventory; SendGrid strategy pagination examples | SES uses direct deletion; SMTP has no inventory. SMTP2GO filtered absence is tested separately. |
| L05–L08 | Lettermint malformed later-page parameterization and HTTP failures; SendGrid malformed-entry and later-page examples; SMTP2GO malformed lookup examples; HTTP-level `operations/sender_provider_response_parity_spec.rb` | Transport/SDK boundaries are fake; partial inventories are never returned on failure. |
| L09 | Lettermint cursor-cycle/malformed-cursor examples and collision refusal examples | Cursor-specific; not applicable to SendGrid offset or name-targeted SES/SMTP2GO paths. |
| L10 | SendGrid generated inventories of 0/49/50/51/1000 entries | Asserts 1/1/2/2/21 requests, including terminal empty pages. |
| L11–L13 | Supported SMTP2GO shapes; unrelated-domain matching; early-match versus failed full inventory; list 404 versus target deletion 404 examples | SMTP2GO has no documented pagination in the dated schema; undocumented caps remain unknown. |
| L14 | Existing first-match behavior retained | Conflicting duplicate provider entries were not independently verified or added as a new acceptance claim. |
| D01–D02 | All remote strategy specs and real-adapter `delete_sender_domain_parity_spec.rb`; `sender_provider_response_parity_spec.rb` | SES absence is delete-time, not an artificial list lookup. |
| D03 / D11 | SES typed/untyped not-found; Lettermint structured delete-only not-found; SendGrid/SMTP2GO unproven errors remain failures | No authoritative missing-target mapping added for SendGrid or SMTP2GO. |
| D04 / D06 / D09 / D12 | Strategy rejection/malformed acknowledgement/blank-error examples; real operation parity | SendGrid 204 and SES empty success are accepted; Lettermint and SMTP2GO require their documented response shapes. |
| D05 | Transport failures in strategy/parity examples, including SES HTTP timeout | Not an exhaustive before/after-dispatch matrix for each provider; no remote-state guarantee after timeout. |
| D07–D08 | Invalid addresses and missing configured credentials in strategy/operation examples | SES environment/instance-profile credential-chain deployment behavior not exercised. |
| D10 | `mail/sender_strategies/smtp_sender_strategy_spec.rb` and operation SMTP examples | Deliberate skip, no remote identity request. |
| O01–O04 | Both real-strategy operation parity files; failed/absent/deleted log assertions | Real adapter methods run, not final-result stubs. O01 is not the exhaustive D01–D09 cross-product. |
| O05–O07 | `operations/delete_sender_domain_spec.rb` malformed/contradictory hash, exception, skip cases; base result-constructor specs | Boundary tests intentionally stub returned strategy results to exercise invalid states. |
| O08 | Lettermint regression: complete preflight followed by fresh later-page cleanup lookup failure | Earlier successful evidence does not mask a fresh failure. |
| C01–C03 | `operations/domains/collision_sender_preservation_spec.rb` and `collision_sender_pagination_regression_spec.rb` | Real Lettermint pagination; SDK-resource list is stubbed, not `list_domains`. |
| C04–C05 | Retained unreadable-reference, external-survivor, removal-candidate, cross-group examples | Existing all-reference/refusal policy remains exercised. |
| C06–C08 | 1000-record/multiple-group request budget, failed-walk retry, datastore-backed dry-run/apply fresh enumeration | Proves request reuse, not a production maintenance-window duration or atomic inventory snapshot. |
| C09–C10 | `apps/api/domains/spec/integration/simple/domain_sender_config_spec.rb`: real SES cleanup denial/deletion/absence | Local removal, normal API response, and failed audit cleanup tested. API-level SMTP skip is not added. |
| C11 | Retained API lease-loss/contention examples and `operations/sender_identity_lease_spec.rb` | Selected lifecycle tests, not every possible concurrent interleaving. |
| C12–C13 | Lettermint later-page duplicate recovery and failed lookup without another create; SMTP2GO failed duplicate-recovery lookup | Existing create-first provider duplicate recovery remains intentional; no new lookup-first creation policy. |
| C14 | Exact fixed collision refusal text, nil cause, no SDK response/token/address, no failed cache entry | Does not claim all adapter logs across the project have been independently scrubbed. |
| C15 | Adapter verification regressions; selected provision/validate/lease suites; caller inspection | Domain-removal call sites inspected, but a dedicated broader domain-removal suite was not run. |

## Callers and lifecycle

Read-only review traced `DeleteSenderDomain`, `DeleteSenderConfig`, domain removal, collision preservation, and strategy provisioning/verification helper callers. Valid identities/nil-for-confirmed-absence are preserved; failed lookup evidence raises into existing consumer error handling. SendGrid `domain_authentications` now raises instead of returning nil on failed enumeration; collision preflight already wraps provider failures and does not cache them. No remaining discovered caller requires a new result-class migration.

Local-removal and locking production code was not changed. The selected API tests demonstrate that remote failure is recorded after local config removal without rollback or incidental response changes. Collision tests demonstrate that unknown inventory refuses preflight rather than authorizing removal. These observations are narrower than a project-wide persistence/security guarantee.

## Finding ledger and conclusion

| Stable IDs from delegated work | Final disposition |
|---|---|
| DEL-01 | Fixed/retested: SES failures no longer become operation success. |
| DEL-02 | Fixed/retested: malformed or contradictory deletion hashes fail validation. |
| DEL-03 | Fixed/retested: absence/skip/deletion separated; blank exceptions get fallback errors. |
| DEL-04 / DEL-06 | Fixed/retested: SendGrid outcome integration and SMTP2GO rejected lookup integration. |
| DEL-05 / EXT-LM-1 | Resolved/retested: Lettermint migrated; final parity and consolidated suites pass. |
| DOC-S2G-1 | Resolved for the dated published v3.0.2 contract; final acknowledgement handling follows it. |
| DOC-S2G-1-NF | Unspecified provider semantics; conservative failure retained. No verified idempotent missing-target error mapping. |
| DOC-S2G-1-ALT | Legacy variants preserved/tested; independent provider documentation remains unavailable. |
| DOC-S2G-1-CURRENT | Unresolved evidence limit: current deployment contract not independently observed. |
| Final independent review | No concrete introduced failure scenario found; final SMTP2GO revision reconciled. Review is not proof of absence of defects. |

The focused lookup and cleanup-reporting regressions pass. The full abstraction is not required for those results. This does **not** establish complete coverage of the proposed acceptance matrix or unconditional readiness for large-scale destructive execution. Remaining verification includes a complete broader lane run, current SMTP2GO contract confirmation for installations using it, and the explicitly partial coverage above. Proxy trust, tenant authorization, sessions, CSRF, SAML, and unrelated listing paths were not audited by this work.
