# 1. Creation commit

Status: Direction approved by the user in conversation; not evidence of implementation or release approval. Requirements below paraphrase those decisions.

## Purpose and scope

Stable V3 supports existing session authentication and explicitly permitted guest operations only; external tokens are excluded. Secret creation has one commit boundary: a complete encrypted secret/receipt pair with trusted ownership, provenance, domain metadata and expiration.

## Requirements

- Validation and preparation precede persistence.
- Commit requires the complete pair and all security-required registrations; these registrations are not optional follow-up work.
- Confirmed success means the complete pair is committed. A partial pair is never successful.
- Optional nonessential follow-up failures, including metrics failures, are logged safely and do not fail committed creation.
- An exception or lost acknowledgment alone does not prove rollback or absence of writes. Internal persistence evidence distinguishes confirmed incomplete persistence from complete pairs and unconfirmed outcomes, without a third user-facing state.
- Creation, [failure handling](02-creation-failures.md), [runtime validation](04-runtime-validation.md) and [scheduled cleanup](03-consumption-cleanup.md) form one simple behavior, not a new recovery framework.

## Acceptance

- Commit depends on required persistence and security registrations, not optional follow-up completion.
- Failures before, during and after persistence have internally distinguishable evidence, without partial success responses.
- Repeated internal handling neither recreates expired records nor extends expiration.
- The persistence primitive's actual model hooks and failure behavior support the boundary; a transaction wrapper alone is insufficient evidence.

## Exclusions and unresolved implementation details

External-token authentication, client recovery endpoints, automatic creation retries and a generic recovery framework are excluded. The persistence primitive and inventory of security-required registrations versus optional effects require implementation inspection. Lost results follow [creation failure handling](02-creation-failures.md); stable release evidence follows [release validation](05-release-validation.md).
