---
# docs/specs/custom-mail-sender/sender-identity-validation-report.md
---


# Sender identity fixes: validation report

Date: 2026-10-16. Status: focused fixes implemented and tested; not blanket production-readiness approval. Revision: 2026-10-16, provider-contract review added below. Revision: 2026-10-17, `lettermint` 0.2.1: deletion absence reads `NotFoundError#code`, and the gem's live-captured 404 bodies are recorded under Lettermint. Revision: 2026-10-16, remaining runtime work: SendGrid returned-count pagination, case-insensitive domain-name matching, the SMTP2GO v3.0.0 removal acknowledgement, and removal-outcome reporting are implemented (`c62148f200` through `95597d2c5f`); see [This run](#this-run-working-tree-on-9620a1ff55). Revision: 2026-10-17, PR #4814 review: a top-level SMTP2GO `error`/`error_code` refuses the v3.0.2 `data.domains` acknowledgement as well as the request-ID-only one (`33d7cf3d36`); the parity spec's SendGrid request matchers are anchored (`8dc797a2a4`); the `remove_domain_try.rb` spy returns the full deletion contract and asserts the `sender_cleanup` that `RemoveDomain` logs (`4fd585c2f7`); and `Smtp2goClient` raises on a top-level `error`/`error_code` in any 2xx response, so a `/domain/view` error envelope no longer reads as absence (`3305d18bb6`). Focused runs on `3305d18bb6`: `smtp2go_client_spec.rb`, `sender_strategies/`, `delivery/smtp2go_spec.rb`, `feedback_spec.rb`, `email/sync_provider_feedback_spec.rb`, `sender_provider_response_parity_spec.rb`, `delete_sender_domain_parity_spec.rb`, and `delete_sender_domain_spec.rb` 635/0 (seed 35659); `remove_domain_try.rb` 12/0. Before their fixes, the four removal regressions reported `:deleted`, the two view regressions reported `:absent`, and the two tryout success assertions got `[:warn, "failed"]`. Revision: 2026-10-17, PR #4814 Claude review of `4c8af44f41`: `bin/ots domains remove` and the colonel removal endpoint report `sender_cleanup`, and a `failed` cleanup exits 1 from the CLI and replaces the admin screen's success toast with a warning (`bb351444c8`); the SendGrid reference describes case-insensitive full-name matching (`aa8e45619f`). Focused runs on `bb351444c8`: unit lane `spec/cli/domains_command_spec.rb` and `apps/api/colonel/spec/logic/colonel/remove_custom_domain_spec.rb` 88/0 (seed 3056); Vitest `AdminDomainDetail.spec.ts` and `useAdminDomains.spec.ts` 33/0.

Historical tested state: commit `9ce521378f` on `feat/domains-resolve-collisions-feedback` (commits `4cdaf69a36` through `9ce521378f`, based on `01cfb53244`). The focused commands below ran at `0e9389a40b`, except for a whitespace-only alignment change in `collision_sender_preservation.rb` that the commit includes; the full unit lane ran on the tree committed as `9ce521378f`. No live-provider requests were made by this work; the Lettermint 404 capture cited under Lettermint was made by the gem's maintainers. This report is execution evidence, not an accepted project guarantee.

References: [design proposal](sender-identity-contracts-design.md), [coverage specification](sender-identity-contracts-test-coverage.md), [preparation evidence and deployment checklist](sender-identity-contracts-preparation.md).

Preparation addendum (2026-10-16): public-source and static configuration checks are recorded separately in the preparation record; they do not rerun or extend the historical test results below. Current SES clients explicitly supply two-part credentials, bypassing the default chain and omitting session tokens. Actual deployed configuration remains untested.

Current tested state: the working tree on `9620a1ff55` (same branch), committed afterwards as `c62148f200` through `95597d2c5f`. The committed code matches the tested tree except a comment on `CollisionResolution::Removal` and the collision spec's connection-pool fixture (`95597d2c5f`), which have not been run. The working tree was clean when this run started; no ambiguity-detection code existed to reconcile with the conflicting-identity scope decision. Results marked historical belong to their recorded revision and do not validate this run; [This run](#this-run-working-tree-on-9620a1ff55) lists the commands executed against the working tree.

## Implemented scope

- Every strategy produces a validated hash with `outcome`, derived `deleted`, nonempty `message`, and `error`. `DeleteSenderDomain` rejects malformed or contradictory results instead of inferring success from a missing error.
- Deletion, confirmed absence, deliberate skip, and failure have distinct operation log outcomes. The operation retains `success?`, `message`, and `error`, and also exposes `outcome`.
- Lettermint individual lookups and complete inventories share cursor traversal and entry validation. Individual lookup may stop on a valid page containing the target; absence and bulk inventory require exhaustion. Later-page failures and cursor cycles raise rather than exposing partial inventories.
- SendGrid retains limit/offset pagination and configured deletion-ID overrides. Malformed entries, including a matching domain without a valid numeric ID, raise. The offset advances by the number of entries returned, and only an empty page ends a walk; a page larger than the requested limit, or one repeating an ID from an earlier page, raises.
- SendGrid (`domain_authentication_id`) and Lettermint (`domain_entry`) compare domain names case-insensitively over the full name with `casecmp?`, as SMTP2GO's `extract_domain_entry` already did. Individual lookup, inventory matching, verification, Lettermint duplicate-create recovery, deletion, and collision preflight share these matchers. Entries and provider IDs are returned unchanged.
- SMTP2GO retains filtered domain lookup and supported legacy entry shapes, but rejects malformed/rejected evidence. Removal accepts the two documented HTTP 200 acknowledgements described below: the v3.0.0 envelope with a nonempty string `request_id` and no `data`, and the archived v3.0.2 `data.domains` without the target. `Smtp2goClient#post_envelope` returns the parsed envelope for this purpose. Both `#post` and `#post_envelope` raise on a 2xx response that carries `error`/`error_code` under `data` or at the top level, for every caller. Removal adds no post-removal lookup and infers no absence from generic errors.
- SES still deletes directly by name; SDK `NotFoundException` means absence. SMTP reports a deliberate skip.
- Removal-outcome reporting: collision removal keeps the teardown's `sender_cleanup` when the `domain.remove` audit write then fails (`Domains::Remove#sender_cleanup`). Customer `RemoveDomain` logs `sender_cleanup` through `Onetime::LoggerMethods#app_logger` on the normal and lease-loss paths, at warn for `failed`; its response is unchanged. `bin/ots domains remove` prints the outcome on every apply and emits it under `--json`; on `failed` it omits "Removal complete" and exits 1. The colonel `DELETE /api/colonel/domains/:extid` response carries `details.sender_cleanup` (null on a dry run) and logs it through `app_logger`, at warn for `failed`; the admin domain screen shows a warning instead of the success toast for `failed`.
- No lookup result-class hierarchy, conflicting-identity detection, retries, reconciliation queue, local rollback, locking changes, credential changes, or public API schema changes were introduced.

## Provider evidence and limits

### Lettermint

Installed `lettermint` 0.2.1 source: `Resources::Domains#list(page_size: nil, page_cursor: nil, ...)`; `Resources::Base#build_params` maps these to `page[size]` and `page[cursor]`. The SDK documents a default page size of 30 and returns parsed response bodies without transforming pagination metadata. `HttpClient#build_error` raises `NotFoundError` on 404 and fills `HttpRequestError#code` and `#details` from an `{"error":{...}}` body (a String `error` becomes `code`; a `{"message":...}` body sets neither). `response_body` keeps a non-JSON body as a String and an empty body as nil (gem `CHANGELOG.md`, 0.2.1, 2026-10-16).

The current [official Team API OpenAPI schema](https://lettermint.co/docs/api-reference/team/0.0.1/lettermint-team-openapi.json) independently specifies:

- `GET /domains`: `page[size]` defaults to 30; the response has a required top-level `next_cursor`, string or null. Null terminates. The response has no `meta` cursor object. The operation documents 200, 401, 403, and 429 responses, and no 404.
- `DomainListData.id` is required and typed `string`; this supports the list-entry string-ID check, not just the delete path parameter. The implementation additionally rejects blank IDs.
- `filter[domain]` is described as "Search by domain name (partial match, case insensitive)". This describes search behavior, not stored or returned casing; the inspected schema gives no storage-casing statement. Local matching still requires a full domain-name match, not a partial filter match.
- `DELETE /domains/{domainId}`: HTTP 200 `MessageResponse`, with a required string `message`.
- `DELETE /domains/{domainId}` 404: the description names error code `RESOURCE_NOT_FOUND`, and the body schema is `anyOf` `ErrorMessage` (a top-level `message` only) or `ApiError` (`error.code` and `error.message`). No example is given.

The release repository's error fixtures include live responses; the fixtures are not shipped in the installed gem. Its [tagged fixture README](https://github.com/onetimesecret/lettermint-ruby/blob/v0.2.1/spec/fixtures/errors/README.md) (lettermint-ruby v0.2.1) states "Captured 2026-10-16 against `https://api.lettermint.co/v1` with a Team token", lists `GET /domains/dom_0000000000000000` as 404 `ApiError`, `code: RESOURCE_NOT_FOUND`, and adds that "`DELETE /domains/dom_0000000000000000` and `GET /projects/dom_0000000000000000` returned a 404 body identical to `not_found_api_error.json`" (`{"error":{"code":"RESOURCE_NOT_FOUND","message":"Resource not found."}}`). An unknown route returned an `ErrorMessage` with no code. This resolves the schema's `anyOf` for the missing-domain case as observed on one account on one day; it is a capture, not a contract.

The deletion request's rescue maps `Lettermint::NotFoundError` whose `code` is `RESOURCE_NOT_FOUND` to absence. A 404 without that code (router `ErrorMessage`, String `error`, proxy HTML, empty body) remains a failure, as does a `RESOURCE_NOT_FOUND` raised by the list endpoint. A missing domain that Lettermint answered in the `ErrorMessage` shape would still report `failed`; the capture shows an `ApiError` response for that account and date, not a universal guarantee. String-error and proxy-HTML fixtures are synthetic, not observed provider responses.

An HTTP-level test exercises the installed SDK's actual query encoding. Other adapter tests use SDK-resource doubles. Neither demonstrates live account behavior.

### SendGrid and SES

SendGrid's official [list](https://www.twilio.com/docs/sendgrid/api-reference/domain-authentication/list-all-authenticated-domains) reference documents `limit` and `offset` enumeration, with no stated default or maximum `limit`, and types each entry's `id` as `number`. The [delete](https://www.twilio.com/docs/sendgrid/api-reference/domain-authentication/delete-an-authenticated-domain) reference lists HTTP 204 with no body as its only response; it documents nothing for a missing domain ID.

Pagination: `each_domain_authentication_page` requests `limit=50`, advances the offset by the number of entries each page returns, and ends a walk only on an empty page. A server that caps pages below the requested limit therefore no longer ends a walk early on a nonempty short page. This is defensive; no cap has been observed, and the only 50-entry default statement found in the inspected sources is the user's unanswered [sendgrid-python #1084](https://github.com/sendgrid/sendgrid-python/issues/1084), not provider confirmation. A page larger than the requested limit raises. The preparation record reports that the list reference describes offsets as multiples of page size (not rechecked in this run); a server that does not honor a returned-count offset and repeats earlier entries makes the walk raise on the repeated ID instead of looping or reporting absence. Neither behavior has been observed against a live account.

Limit: the code accepts only a positive `Integer` ID. JSON integer IDs parse to `Integer`; a non-integral number would be rejected as a malformed entry and fail the lookup. The official validate-domain reference types its input and returned ID as `integer`, unlike the list/retrieve `number` schemas; see the preparation record for citations. This supports integer semantics but does not establish positivity or exclusively integer JSON serialization across endpoints.

SES mappings were checked against installed `aws-sdk-sesv2` 1.110.0. Parity tests use the real SDK HTTP/error translation, including empty success responses and typed versus untyped 404 errors. Deployment credential chains were not exercised.

### SMTP2GO

Live developer documentation returned HTTP 403 (a firewall block page). The official published OpenAPI 3.1.0 document titled SMTP2GO API v3.0.2 was recovered from the official documentation page's archived ReadMe `ssr-props`, not from a third-party interpretation.

Evidence: [Common Crawl index record](https://index.commoncrawl.org/CC-MAIN-2025-30-index?url=developers.smtp2go.com/reference/view-sender-domains&output=json), capture 2025-07-08 01:56:45 UTC, WARC record `a2a203ef-9979-490f-9ccd-cb18070e815b`, compressed range `166407985–166468319`; recovered payload SHA-1 matched `CMIMM46HPFMVV2FZBZMKB267INCNXEB2`.

That dated schema specifies:

- `/domain/view` optional domain filter: “(Optional) If provided, will only retrieve records for this domain”. The request body has only `domain` and `subaccount_id`; no pagination mechanism is documented in that operation. This does not independently exclude undocumented server-side caps.
- Response `data.domains` is an array, with nested `domain.fulldomain` holding the full name. The official WordPress client corroborates the envelope: [`WordpressPluginAdmin.php` L408–L414](https://github.com/smtp2go-oss/wordpress-plugin/blob/814614240f963c3830cae360deaf8a6c00023029/smtp2go/WordpressPluginAdmin.php#L408-L414) calls `domain/view` and keeps `data`, and the [validation partial L13–L25](https://github.com/smtp2go-oss/wordpress-plugin/blob/814614240f963c3830cae360deaf8a6c00023029/admin/partials/smtp2go-wordpress-plugin-validation-display.php#L13-L25) iterates `domains` and reads `domain->fulldomain`.
- `/domain/remove` HTTP 200 is described as “Sender domain removed”; its example is `{"request_id":"...","data":{"domains":[]}}`. It does not define a `success` boolean. Final code validates this acknowledgement without assuming immediate consistency from an extra lookup.
- Missing-domain error semantics are unspecified. Generic 404/not-found text therefore remains failure. Legacy alternate entry shapes remain supported and tested, but were not independently documented by this schema.

The official [GitHub Pages v3.0.0 reference, Remove Sender Domain](https://smtp2go.github.io/smtp2go.apidocs/#remove-sender-domain), separately documents `POST /domain/remove`, HTTP 200, "Success – sender domain removed from account", with a success example containing only `{"request_id":"40cbb6f2-935f-11e7-b5be-480fcf01a6f2"}`. Its success field list contains only string `request_id`; no `data` collection or `success` boolean is specified. This differs from the archived v3.0.2 example, but does not establish which variant current deployments return.

Removal acknowledgement: `Smtp2goClient#post_envelope` applies the same status, invalid-JSON, and `error`/`error_code` failures as `#post` (under `data` or at the top level), and returns the parsed envelope. `Smtp2goSenderStrategy#removal_acknowledged?` refuses any envelope with a top-level `error`/`error_code`, then accepts an envelope with `data` only when `data.domains` is a valid list without the target (v3.0.2), and an envelope without `data` only when it carries a nonempty string `request_id` (v3.0.0). An empty envelope, an empty or non-object body, `data: null`, `data: {}`, and a non-string or blank `request_id` remain failures. `/domain/view` validation is unchanged: a view response without `data.domains` still fails.

A commit-pinned [third-party v3.0.4 harvest](https://github.com/api-evangelist/smtp2go/blob/b078fa4283fb4b5d287ccb05229d2f12410b60e8/openapi/_original/smtp2go-openapi-original.yml#L2689-L2737) also describes `request_id` plus `data.domains` for removal. Its `info.x-harvest` says `harvested: '2026-08-13'` and names the provider's documentation MCP endpoint as its source. This is a research lead, not independently verified provider evidence; the September 2, 2026 documentation date supplied in review was not independently verified.

Both documented removal variants are accepted. Which variant, if either, current deployments return remains unverified, as do missing-domain error semantics and filtered-view completeness.

### Domain casing

`SendGridSenderStrategy#domain_authentication_id`, `LettermintSenderStrategy#domain_entry`, and `Smtp2goSenderStrategy#extract_domain_entry` compare full domain names with `casecmp?`. Provider IDs are not case-folded, and stored names, request targets, and domain canonicalization are unchanged; collision preflight already lower-cases SES/SMTP2GO name targets. None of the inspected provider references specifies stored or returned casing, so this addresses a conditional failure scenario, not observed provider behavior.

Consequence under the conflicting-identity scope decision: if one account listed two entries differing only in case with different IDs, both now match and the first is selected. That is the deferred L14 case; no detection was added.

## Executed commands

### This run: working tree on 9620a1ff55

The checkout already contained `.test-mode`. All Ruby tests used `tests/lanes/run`; provider HTTP/SDK boundaries were stubbed and no live-provider request was made.

```sh
tests/lanes/run unit --quiet \
  --only spec/unit/onetime/mail/sender_strategies \
  --only spec/unit/onetime/mail/sender_strategies_spec.rb \
  --only spec/unit/onetime/mail/smtp2go_client_spec.rb \
  --only spec/unit/onetime/operations/delete_sender_domain_spec.rb \
  --only spec/unit/onetime/operations/delete_sender_domain_parity_spec.rb \
  --only spec/unit/onetime/operations/sender_provider_response_parity_spec.rb \
  --only spec/unit/onetime/operations/domains/collision_sender_preservation_spec.rb \
  --only spec/unit/onetime/operations/domains/remove_spec.rb \
  --only apps/api/domains/spec/logic/domains/remove_domain_spec.rb
```

Result: **666 examples, 0 failures**, seed `6291`.

Datastore-backed files, run one at a time with `tests/lanes/run unit --quiet --only <file>`: `domains/collision_sender_pagination_regression_spec.rb` 3/0, `domains/failure_audit_spec.rb` 12/0, `domains/teardown_spec.rb` 34/0, `provision_sender_domain_spec.rb` 34/0, `validate_sender_domain_spec.rb` 18/0, `sender_identity_lease_spec.rb` 11/0 (examples/failures, paths under `spec/unit/onetime/operations/`). `domains/collision_resolution_spec.rb` was run in five line-number chunks; every example passed except `:817` with `only: false`, which selected a billing-protected group (`coll-ab137471.example`) left in this checkout's lane database by earlier runs aborted mid-run, and skipped it. That example passed in the full unit lane below.

```sh
tests/lanes/run simple --quiet --only apps/api/domains/spec/integration/simple/domain_sender_config_spec.rb
tests/lanes/run api --quiet --only spec/api/domains/remove_domain_role_gate_spec.rb \
  --only spec/api/domains/domain_scope_enforcement_spec.rb
tests/lanes/run unit
```

Results: simple **76 examples, 0 failures**; api **31 examples, 0 failures**; full unit lane exit 0 in 129 s, with `try:unit` 8350 testcases passed, 0 failed in 362 files, and `spec:fast` 16256 examples passed, 13 pending, 0 failed (counted from the lane's worker status file, which includes all 144 `collision_resolution_spec.rb` examples).

`bundle exec rubocop --force-exclusion` on the changed library files and their strategy directory: 11 files inspected, no offenses. `git --no-pager diff --check`: passed.

Environment limits observed in this run:

- Focused runs of the datastore-backed collision and teardown specs failed with `Errno::EADDRNOTAVAIL` on `127.0.0.1:2163`, and the runner reported the services lost mid-run (exit 69). Every failure in those runs carried that error. Cause: in the unit lane Familia has no connection pool, and its fallback opens a new client for every `dbclient` lookup, exhausting the client's ephemeral ports (about 16,000 sockets in `TIME_WAIT` after one file). The operator reproduced the churn on committed `9620a1ff55` without these changes; that run is operator-supplied evidence, not repeated here.
- `collision_resolution_spec.rb` now installs the `SetupConnectionPool` provider around its datastore examples, as the WATCH specs do. That fixture was added after the full unit lane above; its rerun is blocked because the test Valkey on 127.0.0.1:2163 stopped accepting connections and the runner could not start compose (podman API socket unavailable).
- The leftover fixtures (46 keys in this checkout's unit-lane database) were not flushed: the flush command was refused by the session's permission policy.

### Historical: tested state 9ce521378f

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

`tests/lanes/run unit` completed on the tree committed as `9ce521378f` (`lettermint` 0.2.1): `try:unit` 8350 testcases passed, 0 failed in 362 files; `spec:fast` exit 0; lane wall time 122 s, exit 0. An earlier `--quiet` attempt before the final SMTP2GO acknowledgement revision had timed out at 120 seconds. No full simple lane, production execution, or real-provider cleanup was run; CI status is recorded on the pull request, not here.

Regression capture: the expanded SendGrid/SMTP2GO baseline produced 51 failures across 170 examples before those fixes. The Lettermint baseline also failed the new pagination/outcome regressions; its first capture included an invalid test-token fixture, so that capture is not a clean behavioral failure count. No command, seed, or base commit was recorded for these baseline runs, so the counts cannot be reproduced from this report. Obsolete absence-as-deleted and missing-data-as-nil expectations were updated explicitly.

## Coverage reconciliation

Status reflects this run's working tree; rows are evidenced by examples that passed in [This run](#this-run-working-tree-on-9620a1ff55). Paths below are under `spec/unit/onetime/` unless an API path is named. “Covered” describes the identified examples, not every provider/scenario combination in the proposal. “Partial” means the examples exercise the scenario with the limit shown. “Deferred” means a scope decision excludes the row.

| IDs | Status | Evidence | Applicability / limits |
|---|---|---|---|
| L01–L04 | Covered | `mail/sender_strategies/lettermint_lookup_regression_spec.rb`: later target, early target, exhausted absence, empty inventory; `sendgrid_sender_strategy_spec.rb`: first-page and later-page targets, empty-page exhaustion, empty inventory | SES uses direct deletion; SMTP has no inventory. SMTP2GO filtered absence is tested separately. |
| L05–L08 | Covered | Lettermint malformed later-page parameterization and HTTP failures; SendGrid malformed-entry and later-page examples; SMTP2GO malformed lookup examples; HTTP-level `operations/sender_provider_response_parity_spec.rb` | Transport/SDK boundaries are fake; partial inventories are never returned on failure. |
| L09 | Covered | Lettermint cursor-cycle/malformed-cursor examples and collision refusal examples | Cursor-specific; not applicable to SendGrid offset or name-targeted SES/SMTP2GO paths. |
| L10 | Covered | `sendgrid_sender_strategy_spec.rb` `[L10]`: generated 0/49/50/51/1000-entry inventories through inventory, individual absence, and deletion absence | Asserts 1/2/2/3/21 requests at offsets advanced by returned count; a short first page requires the next-offset request. |
| L11–L13 | Covered | Supported SMTP2GO shapes; unrelated-domain matching; early-match versus failed full inventory; list 404 versus target deletion 404 examples | SMTP2GO has no documented pagination in the dated schema; undocumented caps remain unknown. |
| L14 | Deferred | None; existing first-match selection retained | Scope decision 2026-10-16 in the design's Alternatives and decisions. Case-insensitive matching means entries differing only in case now count as the same domain; the first is selected. |
| L15 | Covered | SendGrid: lookup, inventory, deletion by ID 42, verification for an upper-case sender. Lettermint (`lettermint_lookup_regression_spec.rb`): lookup, inventory, deletion, duplicate-create recovery, verification. `collision_sender_preservation_spec.rb`: shared case-variant identities protected for both providers | IDs (`Dom_MixedCase-ID`, `Remote-1`) are asserted unchanged; partial and unrelated names (`sub.example.com`, `example.com.evil`) do not match. SendGrid provisioning creates directly and has no recovery lookup. |
| L16 | Covered | `sendgrid_sender_strategy_spec.rb`: entries served 2/2/1/0 with `limit=50` at offsets 0/2/4/5 for later-target lookup, inventory, absence, deletion, and later-page failure; `operations/sender_provider_response_parity_spec.rb`: same through the real HTTP client and `DeleteSenderDomain` | A failed later page exposes no inventory and deletes nothing. |
| L17 | Covered | 51-entry page rejected in lookup, inventory, deletion, and verification; HTTP-level operation parity | Oversized pages authorize no absence, creation, or deletion. Also: a page repeating an earlier page's IDs fails instead of looping. |
| D01–D02 | Covered | All remote strategy specs and real-adapter `delete_sender_domain_parity_spec.rb`; `sender_provider_response_parity_spec.rb` | SES absence is delete-time, not an artificial list lookup. |
| D03 / D11 | Covered (SES, Lettermint); not applicable (SendGrid, SMTP2GO) | SES typed/untyped not-found; Lettermint `NotFoundError` with `RESOURCE_NOT_FOUND` at the delete endpoint, and message-only, String-error, proxy-HTML, and list-endpoint 404 regressions; SendGrid/SMTP2GO unproven errors remain failures | Neither SendGrid nor SMTP2GO documents a missing-target response, so no absence mapping was added for them. |
| D04 / D06 / D09 / D12 | Covered | Strategy rejection/malformed acknowledgement/blank-error examples; real operation parity | SendGrid 204, SES empty success, Lettermint `MessageResponse`, and both SMTP2GO removal variants are accepted; malformed acknowledgements fail. |
| D13 | Covered | `mail/smtp2go_client_spec.rb` `#post_envelope`; `smtp2go_sender_strategy_spec.rb` `[D13]` accept/reject matrix; `sender_provider_response_parity_spec.rb` `[D13]` through the real client, strategy, and operation | Request-ID-only success is `deleted` with one view and one remove request. Rejected: blank, whitespace, non-string, or null `request_id`; top-level `error`/`error_code`, with or without an empty `data.domains`; `data: null`/`{}`/`[]`; non-object JSON; HTML; HTTP 403 with a `request_id`; v3.0.2 lists retaining the target. `/domain/view` stays strict. |
| D05 | Covered | `delete_sender_domain_parity_spec.rb` `[D05]`: lookup timeout before any delete request and read timeout on the dispatched delete request for SendGrid, SMTP2GO, and Lettermint; SES connection timeout and read timeout | Each reports `failed`; no assertion about remote state after a timeout. |
| D07–D08 | Partial | Invalid addresses and missing configured credentials in strategy/operation examples | SES environment/instance-profile credential-chain deployment behavior not exercised. |
| D10 | Covered | `mail/sender_strategies/smtp_sender_strategy_spec.rb` and operation SMTP examples | Deliberate skip, no remote identity request. |
| O01–O04 | Covered (O01 partial) | Both real-strategy operation parity files; failed/absent/deleted log assertions | Real adapter methods run, not final-result stubs. O01 is not the exhaustive D01–D09 cross-product. |
| O05–O07 | Covered | `operations/delete_sender_domain_spec.rb` malformed/contradictory hash, exception, skip cases; `mail/sender_strategies/base_sender_strategy_spec.rb` `#deletion_result` and `#deletion_error_message` examples | Boundary tests intentionally stub returned strategy results to exercise invalid states. |
| O08 | Covered | Lettermint regression: complete preflight followed by fresh later-page cleanup lookup failure | Earlier successful evidence does not mask a fresh failure. |
| C01–C03 | Covered | `operations/domains/collision_sender_preservation_spec.rb` and `collision_sender_pagination_regression_spec.rb` | Real Lettermint pagination; SDK-resource list is stubbed, not `list_domains`. |
| C04–C05 | Covered | Retained unreadable-reference, external-survivor, removal-candidate, cross-group examples | Existing all-reference/refusal policy remains exercised. |
| C06–C08 | Covered | 1000-record/multiple-group request budget, failed-walk retry, datastore-backed dry-run/apply fresh enumeration | Proves request reuse, not a production maintenance-window duration or atomic inventory snapshot. |
| C09–C10 | Covered | `apps/api/domains/spec/integration/simple/domain_sender_config_spec.rb`: real SES cleanup denial/deletion/absence; `[C10]` SMTP config through the real SMTP strategy | Local removal, normal API response, and audit `provider_cleanup`/`provider_outcome` tested; SMTP records `completed`/`skipped` with no HTTP request. |
| C11 | Covered | Retained API lease-loss/contention examples and `operations/sender_identity_lease_spec.rb` | Selected lifecycle tests, not every possible concurrent interleaving. |
| C12–C13 | Covered | Lettermint later-page duplicate recovery and failed lookup without another create; SMTP2GO failed duplicate-recovery lookup | Existing create-first provider duplicate recovery remains intentional; no new lookup-first creation policy. |
| C14 | Covered | Exact fixed collision refusal text, nil cause, no SDK response/token/address, no failed cache entry | Does not establish that all adapter logs across the project are scrubbed. |
| C15 | Covered | Adapter verification regressions; provision/validate/lease suites; `domain_sender_config_spec.rb` `[C15]` domain removal with real SES cleanup deleted/absent/failed; `remove_domain_spec.rb`; `domains/collision_resolution_spec.rb` audit-failure propagation; `domains/remove_spec.rb` `#sender_cleanup`; `spec/cli/domains_command_spec.rb` remove outcomes; `colonel/remove_custom_domain_spec.rb` sender cleanup outcome; `AdminDomainDetail.spec.ts` failed-cleanup warning; caller review below | Customer removal response unchanged; the colonel response adds `details.sender_cleanup`. Vhost cleanup outcome remains log-only and untested here. |

## Callers and lifecycle

Read-only review traced `DeleteSenderDomain`, `DeleteSenderConfig`, domain removal, collision preservation, and strategy provisioning/verification helper callers. Valid identities/nil-for-confirmed-absence are preserved; failed lookup evidence raises into existing consumer error handling. SendGrid `domain_authentications` now raises instead of returning nil on failed enumeration; collision preflight already wraps provider failures and does not cache them. No remaining discovered caller requires a new result-class migration.

`CollisionSenderPreservation` no longer carries a `:malformed` fallback for a Lettermint entry without an ID: `list_domains` and `domain_entry` raise on such an entry first. Its identity check now guards only the configured SendGrid `domain_id` override, which no listing validates; a blank or non-scalar override refuses with "sendgrid gave no usable identity for the sender domain". `Mailer.provider_credentials('sendgrid')` builds only `api_key`, so installation credentials never supply that override today.

Callers of the changed matchers and paginators, reviewed in this run: SendGrid `find_domain_id` (verification, deletion) and `domain_authentications` plus `domain_authentication_id` (collision preflight); Lettermint `find_domain_by_name` (verification, deletion, duplicate-create recovery) and `list_domains` plus `domain_entry` (collision preflight); SMTP2GO `extract_domain_entry` (provisioning recovery, verification, lookup, v3.0.2 removal). Only `/domain/remove` uses `Smtp2goClient#post_envelope`; `Delivery::Smtp2go` and every other SMTP2GO call keep `#post`. Return shapes are unchanged: identity, entry, or list on success, nil for confirmed absence, raise on failed evidence.

`Teardown#sender_cleanup` consumers: `Domains::Remove` records it in the `domain.remove` audit detail and now also exposes it as `#sender_cleanup`, which `CollisionResolution#remove` reads when the audit write raises `AuditWriteFailure`, so a `removed_audit_failed` removal counts toward `sender_cleanup_failed` and the group's cleanup errors. Customer `RemoveDomain` logs it; it adds no audit event, persisted record, or response field, because the customer path has no audit trail of its own and adding one is separate design work. `bin/ots domains remove` and the colonel `RemoveCustomDomain` report it to the operator, as described under the removal-outcome summary above. `Teardown#delete_vhost` failures remain log-only and are outside these contracts.

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
| DOC-S2G-1-V300 | Official v3.0.0 documents request-ID-only removal success, unlike the v3.0.2 capture; the earlier code reported failure for that response. | Fixed in this run (RT-S2G-V300): both documented variants accepted, D13 covered through the real client. Current deployment response unverified. The third-party v3.0.4 harvest is only a lead. |
| Final independent review | Review of the final diff. | No concrete introduced failure scenario found; final SMTP2GO revision reconciled. Review is not proof of absence of defects. |
| R1 | The O05–O07 row cited base result-constructor specs that did not exist. | Fixed: `#deletion_result` and `#deletion_error_message` examples in `base_sender_strategy_spec.rb`. |
| R2 | The coverage table had no status per ID. | Fixed: Status column. |
| R3 | The Lettermint delete 404 is `anyOf` `ErrorMessage`/`ApiError`; only `ApiError` maps to absence. | Resolved with `lettermint` 0.2.1: the rescue reads `NotFoundError#code`, and the gem's live capture shows the missing-domain 404 is `ApiError` `RESOURCE_NOT_FOUND`. The message-only regression example still pins the failure for router 404s. |
| R4 | SendGrid types `id` as `number`; the code requires a positive `Integer`. | Recorded as a limit. |
| R6 | The WordPress citation pointed at lines that read only `data`. | Fixed: citation covers the admin call and the partial that reads `domains` and `fulldomain`. |
| R7 | An unnamed skill's `meta.cursor` example was referenced. | Fixed: replaced with the schema fact (no `meta` cursor object). |
| R8 | The earlier whitespace check did not cover untracked spec files. | Fixed: check runs against the base commit. |
| R9 | The baseline failure counts have no command, seed, or base commit. | Recorded; not recoverable. |
| R10 | The tested-state line named an uncommitted tree. | Fixed: names the tested commit. |
| R11 | Ledger IDs had dispositions but no finding text. | Partly fixed: Finding column reconstructed from the code changes; original text unavailable. |
| R12 | `CollisionSenderPreservation` kept an unreachable `:malformed` fallback, and its refusal text described a listing. | Fixed: fallback removed; refusal reworded for the configured override and covered by two examples. |

### Provider-contract document review

The following material findings concern the three documents and the citation-only code change. "Addressed" means the documents now describe the evidence and proposed behavior accurately; it does not mean the runtime gap is fixed.

| ID | Finding and materiality | Document disposition and evidence | Verification |
|---|---|---|---|
| DREV-LM | Material: design and fixture guidance called verified pagination inputs unverified; report omitted list-ID typing and filter semantics. | Addressed in design provider responsibilities, coverage fixtures, and report Lettermint section. | Rechecked installed 0.2.0 gem and official OpenAPI schema. |
| DREV-SG | Material: short-page completion can yield false absence under a server cap. | Addressed as a revised proposal with returned-count offsets, empty-page termination, oversized-page rejection, updated counts, and L16–L17. Runtime change: RT-SG-PAGE. | Compared current paginator with official list reference and #1084; no cap or 50-entry default inferred from that issue. |
| DREV-CASE | Material: exact matching can miss a case-variant identity. | Addressed as a comparison-only proposal and L15. Runtime change: RT-CASE. | Inspected both exact matchers, SMTP2GO comparator, and cited provider references; stored casing remains unspecified in those sources. |
| DREV-S2G | Material: v3.0.0 success is rejected; treating every empty hash as success would lose validation. | Addressed with both official variants, endpoint-scoped acknowledgement proposal, D13, and DOC-S2G-1-V300. Runtime change: RT-S2G-V300. | Official Pages reference checked; client unwrapping and strategy rejection inspected. Archived v3.0.2 extraction was not repeated; third-party harvest remains a lead and its supplied September date is unverified. |
| DREV-CITE | Material: code comment lacked the schema source for the Lettermint error code. | Addressed with an OpenAPI JSON citation in the deletion rescue comment and updated R3 disposition. | Confirmed `DELETE /domains/{domainId}` 404 description in the schema; comment-only diff. |

Documentation revision validation: `git --no-pager diff --check` passed; `bundle exec rubocop --force-exclusion lib/onetime/mail/sender_strategies/lettermint_sender_strategy.rb` inspected one file with no offenses. A Python check resolved all 17 local file/directory/heading links in the three documents. Final diff and finding coverage were reviewed, including a read-only independent review with no findings. No applicable Markdown linter/build was configured in the inspected package scripts or `.github` checks; `.prettierignore` excludes `docs`. No Ruby suites were rerun for documentation and comment-only changes.

External-source checks for this revision: installed Lettermint gem source, official Lettermint schema, official SendGrid list reference, #1084, official SMTP2GO Pages reference (including its anchor), and the pinned third-party harvest were inspected. The previously cited Common Crawl payload and WordPress sources were not revalidated; no current SMTP2GO deployment response or supplied September 2 documentation date was verified. These limits remain explicit rather than being treated as passing checks.

### Runtime implementation ledger (this run)

| ID | Finding | Disposition |
|---|---|---|
| RT-SG-PAGE | SendGrid stopped on a nonempty short page and advanced by the requested limit (DREV-SG, L10, L16). | Fixed: offsets advance by returned count; only an empty page ends a walk; oversized pages raise (L17). |
| RT-SG-LOOP | Advancing by returned count could loop without end if a server ignored the offset and repeated a nonempty page. | Fixed: a page repeating an ID from an earlier page raises. Not observed live. |
| RT-CASE | SendGrid and Lettermint matched domain names case-sensitively (DREV-CASE, L15). | Fixed: `casecmp?` full-name comparison in both shared matchers; IDs unchanged. |
| RT-S2G-V300 | SMTP2GO request-ID-only removal success reported `failed` (DREV-S2G, DOC-S2G-1-V300, D13). | Fixed: `post_envelope` plus `removal_acknowledged?`; malformed and error responses still fail. |
| RT-PROP-COLL | Collision removal lost `sender_cleanup` when the `domain.remove` audit write failed. | Fixed: `Remove#sender_cleanup` read in the `AuditWriteFailure` rescue. |
| RT-PROP-RD | Customer `RemoveDomain` ignored `Teardown#sender_cleanup`. | Fixed as a log through `app_logger`, warn on `failed`; no audit event, persistence, or response change. |
| RT-LOG | Operator instruction: use `Onetime::LoggerMethods` rather than the `OT.info`/`OT.ld` shims. | Done for `RemoveDomain#process`; the category stays `App`, the one the shim inferred for that path. |
| RT-VHOST | Vhost cleanup failures are log-only. | `[risk: not assessed]` Deferred (scope): outside the sender identity contracts. |
| RT-TYPES | `LookupResult`/`InventoryResult` from the design were not introduced. | `[risk: not assessed]` Deferred (scope): behavior uses existing return shapes, with nil only for confirmed absence and raises for failed evidence. |
| RT-DUP | Conflicting provider identities (L14). | Deferred under the 2026-10-16 scope decision; first-match selection retained. |
| RT-ENV-PORTS | Unit-lane datastore specs exhaust client ephemeral ports through Familia's per-lookup fallback clients. | `collision_resolution_spec.rb` installs the boot pool provider around its datastore examples; other datastore specs unchanged. Rerun of that fixture blocked (see This run). |

### PR #4814 review ledger

| ID | Finding | Disposition |
|---|---|---|
| PR-S2G-TOPERR | Greptile and Copilot: `removal_acknowledged?` checked `data` before top-level `error`/`error_code`, so `{"error":"rejected","data":{"domains":[]}}` reported `deleted`. | Fixed `33d7cf3d36`: top-level check first; regressions in the strategy matrix and through the real client. |
| PR-CODEQL | CodeQL alerts 317-322: unanchored `/api\.sendgrid\.com/` matchers in `sender_provider_response_parity_spec.rb`. | Fixed `8dc797a2a4`: one anchored matcher, with a positive assertion that it matches a real DELETE. |
| PR-TRY-SPY | Claude review: the `remove_domain_try.rb` spy returned the pre-contract shape, so cases 2 and 3 ran the invalid-result failure path. | Fixed `4fd585c2f7`: full contract; cases 2-4 assert the logged `sender_cleanup`. |
| PR-SG-ID | Claude review (non-blocking): SendGrid `id` must be a positive Integer; a non-integral serialization such as `123.0` fails the whole walk. | `[risk: correctness] Deferred (merit)`: fails closed (`failed`, no DELETE). No non-integer ID observed. Accepting one would also need normalizing the ID before it is put in the DELETE path. |
| PR-S2G-ACK | Claude review (non-blocking): the removal acknowledgement shares `extract_domain_entry` strictness, so a malformed entry for another domain reports `failed`. | `[risk: none] Deferred (merit)`: fails closed; a later cleanup finds the target absent. |
| PR-CLI-CLEANUP | Claude review of `4c8af44f41`: `bin/ots domains remove` dropped `sender_cleanup`, printing "Removal complete" and exiting 0 after a failed provider deletion; the colonel response omitted it and logged no warning. | Fixed `bb351444c8`: CLI prints and emits the outcome and exits 1 on `failed`; colonel `details.sender_cleanup` plus warn log; admin screen warns. |
| PR-SG-DOC | Claude review (non-blocking): `custom-mail-sender-sendgrid.md` documented exact-string `find_domain_id` matching after the change to `casecmp?`. | Fixed `aa8e45619f`. |
| PR-S2G-EMPTY-DATA | Claude review (non-blocking): a 200 `{"request_id":"…","data":{}}` removal is recorded as `failed`. | No change: `data: {}` is a listed failure under the removal acknowledgement rule above, which accepts `data` only as a valid `data.domains` list. The shape is not documented as a success. If the provider did remove the identity, the cost is a false `failed` report, and the operator finds the identity absent at the provider. |
| PR-S2G-VIEW | Found while fixing PR-S2G-TOPERR, confirmed by QA review: `Smtp2goClient#post` returns only `data`, so a 200 `/domain/view` body with a top-level `error` and an empty `data.domains` reported `absent` and skipped `/domain/remove`. | Fixed `3305d18bb6`: the client raises on top-level `error`/`error_code` in any 2xx response. This also applies to `/email/send` and the feedback endpoints; SMTP2GO documents errors under `data`, so no documented success response changes. |

### Conclusion

The focused, simple, api, and full unit lane runs listed under This run passed for the working tree, except the fixture-only rerun noted there. This does **not** establish unconditional readiness for large-scale destructive execution. Remaining: CI on a pushed revision; a full `simple` lane run; current SMTP2GO response confirmation for installations using it; SES explicit-credential validation in deployment; SendGrid deletion-time missing-target semantics (generic 404 remains failure); the Lettermint message-only 404 alternative (remains failure); vhost cleanup reporting; and the deferred L14 and explicit lookup types. Proxy trust, tenant authorization, sessions, CSRF, SAML, and unrelated listing paths were not audited by this work.
