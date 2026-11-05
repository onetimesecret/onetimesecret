# Sender identity contracts: preparation record

Date: 2026-10-16. Inspected repository revision: `1e9a08086011351dfc4682ab4f06dc45e61a6aae`.

Status: repository and public-source preparation completed; deployment validation and some provider semantics remain unresolved. This is evidence and an execution checklist, not acceptance of the [design](sender-identity-contracts-design.md), an implementation, or production-readiness approval.

Companions: [historical validation report](sender-identity-validation-report.md), [coverage specification](sender-identity-contracts-test-coverage.md).

## Evidence boundary

This pass inspected code, shipped deployment templates, locally installed SDK source, and public documentation. No application boot, authenticated provider request, credential resolution, or deletion was performed. Operator configuration, secret values, deployed processes, and actual account inventories were not inspected. Earlier test results remain attached to their recorded revision; no Ruby suites were rerun for this documentation-only pass.

No additional pagination defect is established beyond the historical Lettermint omission already fixed. SMTP2GO filtered-result completeness and SendGrid server caps remain evidence questions. The SendGrid empty-page termination proposal is defensive behavior, not a finding that the provider currently truncates results.

## Provider evidence and fixture authority

### SMTP2GO

- Current official [view](https://developers.smtp2go.com/reference/view-sender-domains) and [remove](https://developers.smtp2go.com/reference/remove-sender-domain) documentation returned HTTP 403. The documentation [MCP endpoint](https://developers.smtp2go.com/mcp) also blocked anonymous initialization/tool discovery. Current official schema and deployment responses remain unverified.
- The official [v3.0.0 removal reference](https://smtp2go.github.io/smtp2go.apidocs/#remove-sender-domain) documents HTTP 200, “Success – sender domain removed from account”, with only a string `request_id`. The report's archived v3.0.2 schema instead illustrates `request_id` plus `data.domains`. Both are documented success variants; neither establishes today's response. The archived payload was not re-extracted in this pass.
- The [commit-pinned v3.0.4 third-party harvest](https://github.com/api-evangelist/smtp2go/blob/b078fa4283fb4b5d287ccb05229d2f12410b60e8/openapi/_original/smtp2go-openapi-original.yml) was inspected again. Its self-reported 2026-08-13 MCP capture retains nested `domain.fulldomain` and a removal `data.domains` acknowledgement. It remains a research lead, not independently retrieved current provider evidence.
- No inspected source establishes a missing-domain error mapping, alternate legacy entry shapes, or an independent completeness guarantee for the filtered response. Preserve conservative failures and legacy compatibility tests. Do not invent pagination inputs or treat generic 404s as absence.
- Current [client](../../../lib/onetime/mail/smtp2go_client.rb) unwrapping loses `request_id`; request-ID-only success reaches the strategy as `{}` and fails validation. D13 is the pending endpoint-specific regression/fix, not permission to accept arbitrary empty hashes.

### Lettermint

The installed `lettermint` 0.2.1 source and current official [Team OpenAPI 0.0.1 schema](https://lettermint.co/docs/api-reference/team/0.0.1/lettermint-team-openapi.json) confirm cursor arguments/encoding, 30-entry default, required top-level nullable `next_cursor`, required string IDs, and successful DELETE HTTP 200 with a string `message`. Those are not open prep questions.

The release repository's [v0.2.1 fixture README](https://github.com/onetimesecret/lettermint-ruby/blob/v0.2.1/spec/fixtures/errors/README.md) records a maintainer capture on 2026-10-16 against API `/v1`: deleting a missing domain returned structured `RESOURCE_NOT_FOUND`. The [fixture](https://github.com/onetimesecret/lettermint-ruby/blob/v0.2.1/spec/fixtures/errors/not_found_api_error.json) records `error.code` and `error.message`. These fixtures are in the release repository, **not included in the installed gem**. Proxy-HTML and String-error fixtures are synthetic, not observed responses.

This narrows the missing-target ambiguity to a documented alternative not observed in that capture. The official 404 schema still permits message-only `ErrorMessage` as well as structured `ApiError`; one account/day does not remove that alternative. Keep structured `RESOURCE_NOT_FOUND` absence scoped to deletion. Message-only, bodyless, proxy, and list-endpoint 404s remain failures. This pass did not exercise an application account.

### SendGrid

The current official [delete reference](https://www.twilio.com/docs/sendgrid/api-reference/domain-authentication/delete-an-authenticated-domain) documents only HTTP 204 without a body. The [general errors reference](https://www.twilio.com/docs/sendgrid/api-reference/how-to-use-the-sendgrid-v3-api/errors) does not establish missing-target semantics for this endpoint. Deletion-time absence mapping remains unresolved; generic 404 is not sufficient.

The [list](https://www.twilio.com/docs/sendgrid/api-reference/domain-authentication/list-all-authenticated-domains) and [retrieve](https://www.twilio.com/docs/sendgrid/api-reference/domain-authentication/retrieve-an-authenticated-domain) schemas type returned IDs as `number`; the [validate reference](https://www.twilio.com/docs/sendgrid/api-reference/domain-authentication/validate-a-domain-authentication) types its domain-ID input and returned ID as `integer`. Integer semantics have official support, but positivity and exclusively integer JSON serialization are not established across these sources. Retain positive-integer validation as the current implementation restriction, not a universal provider guarantee.

The list reference documents `limit`/`offset`, describes offsets as multiples of page size, and gives no numeric default or maximum. No hidden cap was observed. Current 50-entry short-page termination and proposed returned-count/empty-page termination must remain distinct in fixtures and reporting.

### SES and dependency versions

SES success and typed deletion `NotFoundException` remain covered by the previously recorded SDK tests; no new deletion-response ambiguity was identified. This pass checked source, not those tests again.

[Gemfile.lock](../../../Gemfile.lock) and local gem availability agree on `aws-sdk-sesv2` 1.110.0, `aws-sdk-core` 3.257.0, `aws-sigv4` 1.12.1, `lettermint` 0.2.1, and `sendgrid-ruby` 6.7.0. SendGrid sender management uses direct HTTP rather than that gem; SMTP2GO uses the repository client. Local installation does not prove deployed loaded versions.

## Current credential and deployment behavior

These are code-inspection findings, not observations of running installations.

### Provider and credential selection

[Domain provider selection](../../../lib/onetime/models/custom_domain/mailer_config.rb) uses stored provider, then installation sender provider, then delivery provider. [Mailer](../../../lib/onetime/mail/mailer.rb) supplies installation credentials to provisioning, verification, and deletion; stored domain API keys are not their authority.

| Provider | Current sender-management credential selection |
|---|---|
| SES | Start with nonblank `emailer.user/pass`, then standard AWS key environment variables; override each field with nonempty `email_providers.ses` settings. Region starts with non-placeholder `emailer.region`, then `AWS_REGION`, then the dedicated management override. |
| SendGrid | First nonblank `emailer.sendgrid_api_key`, `emailer.pass`, `SENDGRID_API_KEY`. Resolver returns no `domain_id`; explicit strategy overrides are not currently an installation setting. |
| Lettermint | `emailer.lettermint_team_token`, then `email_providers.lettermint.team_token`, then `LETTERMINT_TEAM_TOKEN`. Team and sending tokens are distinct. |
| SMTP2GO | `emailer.smtp2go_api_key`, then `email_providers.smtp2go.api_key`, then `SMTP2GO_API_KEY`. |
| SMTP | No remote identity or deletion request. |

Lettermint Team-token and SMTP2GO selection use Ruby `||`; a higher-priority empty string blocks fallback. SES overrides are per-field, so partial configuration can mix credential sources. Verify provenance without printing values.

### SES is explicit-key only today

The [sender strategy](../../../lib/onetime/mail/sender_strategies/ses_sender_strategy.rb), [delivery client](../../../lib/onetime/mail/delivery/ses.rb), and [feedback client](../../../lib/onetime/mail/feedback/ses.rb) pass `Aws::Credentials.new(access_key, secret_key)` explicitly. They neither invoke default-chain fallback nor pass `AWS_SESSION_TOKEN`. Roles, profiles, web identity, and temporary three-part credentials must not be assumed supported by these constructors. Adding chain/session-token support is a separate behavior change, not a missing deletion-error mapping.

The [shipped defaults](../../../etc/defaults/config.defaults.yaml) set management region to `CUSTOM_MAIL_SES_REGION || 'us-east-1'`; dedicated management keys fall back to standard AWS keys. Consequences to check in an installation:

- `AWS_REGION=eu-west-1` alone can select Europe for delivery while management still uses `us-east-1`.
- With SMTP delivery and no dedicated/standard AWS keys, management can retain SMTP username/password as the AWS pair.
- Partial overrides can combine a key and secret from different sources.

Provisioning checks required credentials; deletion reports strategy failure. Successful mail delivery does not establish sender-management credentials, permissions, or account/region alignment.

### Process wiring and lifecycle

- [Configuration loading](../../../lib/onetime/config.rb) normally merges defaults under operator YAML; explicit-path loading bypasses that defaults layer.
- [Simple Compose](../../../docker/compose/docker-compose.simple.yml) and [full Compose](../../../docker/compose/docker-compose.full.yml) inject root `.env`. Full-stack worker queue configuration names `email.message.send`; do not assume that this worker consumes domain-validation jobs.
- [Systemd worker example](../../../etc/examples/systemd/onetimesecret-worker.service) loads `/etc/default/onetimesecret` and then sources working-directory `.env`; later assignments can replace earlier ones. These templates are not proof of deployed process settings.
- [Worker startup](../../../lib/onetime/jobs/workers/domain_validation_worker.rb) checks delivery-provider credentials, not independent sender-provider readiness. [Provider verification](../../../lib/onetime/operations/check_provider_verification.rb) can skip the provider call when credentials are missing; DNS-derived verification is not an API credential check.
- [Sender-config deletion](../../../apps/api/domains/logic/sender_config/delete_sender_config.rb) removes local config before cleanup; [domain teardown](../../../lib/onetime/operations/domains/teardown.rb) continues local removal after ordinary cleanup failure. A provider smoke test must not invoke these application removal flows merely to probe error semantics.

## Duplicate selection and caller preparation

Current SendGrid and Lettermint helpers choose the first exact-case domain match; SMTP2GO chooses the first case-insensitive match. Entry validation does not establish uniqueness. No provider duplicate guarantee or live conflicting duplicate was verified.

If one domain is returned with IDs A and B, ordering can change the target between preflight and deletion. Rejecting conflicts across the entire inventory would require full enumeration and conflicts with unconditional early-match lookup. Before implementing L14, choose and document either provider-backed uniqueness, a justified stable selection rule, or ambiguity rejection with the required enumeration cost. Do not silently turn existing first-match behavior into an accepted provider contract.

Caller surfaces reviewed:

| Surface | Preparation consequence |
|---|---|
| [Provisioning](../../../lib/onetime/operations/provision_sender_domain.rb), [verification](../../../lib/onetime/operations/check_provider_verification.rb), [deletion](../../../lib/onetime/operations/delete_sender_domain.rb) | Keep installation credential selection and explicit failure propagation. |
| [SendGrid strategy](../../../lib/onetime/mail/sender_strategies/sendgrid_sender_strategy.rb) | Provisioning creates directly; deletion resolves a fresh ID or uses the explicit override, not stored provisioning metadata. |
| [Lettermint strategy](../../../lib/onetime/mail/sender_strategies/lettermint_sender_strategy.rb) | Deletion and duplicate-create recovery re-resolve identity through shared lookup. |
| [Collision preservation](../../../lib/onetime/operations/domains/collision_sender_preservation.rb) | Successful list cache is provider-scoped for one installation/apply; failed lists are not cached. SES/SMTP2GO targets are computed locally, not remotely verified in preflight. |
| [Test-email delivery](../../../apps/api/domains/logic/sender_config/send_test_email.rb) versus [normal mail](../../../lib/onetime/mail/mailer.rb) | Test email uses a stored domain API key for Lettermint, SendGrid, and SMTP2GO when available; missing keys and SES fall back to the global backend. Normal mail uses the global backend. A successful domain-token test does not validate ordinary delivery credentials or management credentials. |
| Local removal and worker paths above | Preserve local-removal and locking policies; boot success, DNS validation, and test-email success do not prove management readiness. |

Account/region/endpoint are not part of the collision cache key. Keep the existing single installation scope stable during an apply; any future multi-account support requires a separate cache/identity review. Unrelated listing endpoints were not audited.

## Deployment evidence still required

This procedure is prepared, **not executed**. An operator must supply the deployment and authorize account access. Destructive probes require a disposable identity in an isolated provider account/subaccount, never a production sender or a guessed ID.

1. Record deployed commit/image digest and loaded SDK versions for web, relevant workers, and maintenance CLI. Record provider, endpoint, region, credential class, source setting names, and missing/blank flags without values. Do not dump environment, resolved configuration, authorization headers, or tokens.
2. Confirm intended account and region, management permissions, configuration-layer precedence, and actual queue consumers. For SES, validate the explicit key pair; do not test role fallback as if the current constructors supported it.
3. With separate read-only authorization, inspect a known disposable target and a known-absent name through the real client. Record response status, field names/types, pagination metadata, and whether duplicate identities occur. A small successful list does not prove lack of a hidden cap; seek provider confirmation of filtered completeness and uniqueness.
4. Only after destructive authorization, delete the disposable identity once, then repeat that same target-specific request. Record first-delete and repeat-delete status, content type, body shape, structured error code, SDK exception class, and account/region scope. For SendGrid/Lettermint retain the original disposable ID for the repeat request; a fresh lookup would bypass the deletion-time missing-target question.
5. Capture SMTP2GO's original HTTP envelope before `parse_data` removes it. Compare it with both documented success variants. Obtain provider confirmation for any proposed new absence mapping; a single observed error alone does not justify classifying every 404 as absent.
6. Sanitize captures before committing fixtures: remove tokens, addresses, account identifiers and unrelated inventory. Preserve semantic types, status, endpoint, SDK version, observation date, and provenance. Mark synthetic fixtures separately. Do not log raw bodies to application audit records.
7. Add authorized captures to HTTP-level adapter tests and map them to D01/D03/D11/D12/D13 and L11/L13/L14 as applicable. Run focused and broader Ruby suites only through the lane runner and only with the pre-existing `.test-mode` sentinel. Keep deployment observation separate from automated-test results.

## Preparation ledger and implementation gate

All findings below are material to evidence accuracy or execution readiness. “Addressed” means the preparation record is accurate, not that runtime behavior changed. Unresolved provider/deployment items remain blockers to declaring those checks complete; conservative implementation work can proceed without inventing permissive mappings.

| ID | Finding / disposition | Evidence and next verification |
|---|---|---|
| PREP-S2G (DOC-S2G-1, -CURRENT, -NF, -ALT, -V300) | Addressed documentation distinction; currentness, missing-target semantics, legacy shape authority, and filtered completeness unresolved. | Public sources above; 403 blocks current official retrieval. Operator captures/provider confirmation required; D13 remains unimplemented. |
| PREP-LM (R3, DREV-LM, DREV-CITE) | Addressed: structured missing-domain response has maintainer-capture evidence; message-only alternative remains possible. | Installed 0.2.1 source, current schema, tagged fixture README checked; own-account validation unexecuted. |
| PREP-SG (SG-NF-01, R4, DREV-SG) | Addressed documentation distinction; missing-delete mapping and universal ID guarantees unresolved. No new pagination defect established. | Current official list/retrieve/validate/delete/error references checked; targeted provider confirmation needed. |
| PREP-BASE (SID-01, SID-12) | Addressed: historical tests and local versions are not deployed evidence. | Baseline revision and lock/local SDK inspection recorded above. |
| PREP-CREDS (SID-02–SID-05) | Addressed static behavior: explicit SES credentials, region/per-field precedence, token distinctions and blank handling. Deployment correctness unresolved. | Resolver, constructors, defaults and SDK source inspected; value-free deployed provenance check required. |
| PREP-DUP (SID-06) | Unresolved: conflicting identities and accepted selection policy. | Current first-match code inspected; provider guarantee or explicit design decision required before L14 acceptance. |
| PREP-CALLERS (SID-07–SID-10) | Addressed caller/cache/lifecycle preparation; no changes proposed to local-removal policy. | Call sites above inspected; integration regressions required with implementation. |
| PREP-DEPLOY (SID-11) | Addressed template inventory; actual deployment behavior unresolved. | Compose/systemd/config paths inspected; process/account checks above unexecuted. |

Review correction REV-SID-09: addressed by adding the distinct test-email versus ordinary delivery credential paths to the caller table; verified against the cited caller and mailer source. All SID-01–SID-12 and provider research findings are represented in the ledger; unresolved evidence is not counted as completed validation.

## Documentation validation

`git --no-pager diff --check` passed. A Python check validated local file/directory/heading links and whitespace in all four sender-identity documents, including this untracked preparation record. Provider-source and deployment/caller reviewers reconciled their findings against the final documents; the caller correction is recorded above.

No applicable Markdown build/linter was found in `package.json` or the searched `.github` checks; `.prettierignore` excludes `docs`. Ruby tests and live-provider probes were not run. Public sources listed in the provider sections were checked in this preparation session except the explicitly unrepeated Common Crawl extraction. Existing report citations to the WordPress client and sendgrid-python issue #1084 were not revalidated; they are not new evidence from this pass. Current SMTP2GO documentation/MCP access failed as recorded above. Local link checks do not validate external sources or runtime behavior.

The next implementation can address documented acknowledgement variants and synthetic defensive cases while keeping uncertain responses as failures. It cannot label current SMTP2GO behavior, deployment credential correctness, duplicate semantics, or missing-target mappings verified without the remaining evidence.
