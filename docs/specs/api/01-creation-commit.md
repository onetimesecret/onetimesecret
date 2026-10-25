# 1. Creation commit

Status: Proposed. Defines intended behavior, not implemented guarantees.

## Purpose and scope

Secret creation has one explicit commit boundary. The encrypted secret and receipt form a complete pair with trusted ownership, provenance, domain metadata and expiration deadlines.

## Requirements

- Validation and preparation precede persistence.
- Confirmed success means the complete pair is committed. An exception alone is not evidence that nothing was written.
- Required persistence is distinct from optional metrics and follow-up work. Optional failures do not turn a committed creation into a creation failure.
- The implementation exposes this order directly, with narrowly named operations rather than a generic recovery framework.

## Acceptance

- Failures before, during and after persistence have distinguishable outcomes.
- A partial pair is never reported as successful.
- Repeated internal handling neither recreates expired records nor extends deadlines.
- The persistence primitive's actual model hooks and failure behavior support the stated boundary; a transaction wrapper alone is insufficient evidence.

## Exclusions and open decisions

Client recovery endpoints and idempotent POST retries are excluded. The exact required side effects and persistence primitive need selection before implementation. Lost or uncertain results follow [creation failure handling](02-creation-failures.md).
