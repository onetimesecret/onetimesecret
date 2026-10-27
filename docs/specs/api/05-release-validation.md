# 5. Release validation

Status: Direction approved by the user in conversation; not evidence of implementation or release approval. These documents do not approve stable V3 promotion. Requirements below paraphrase the approved decisions.

## Purpose and scope

Release evidence covers [creation commit](01-creation-commit.md), [creation failures](02-creation-failures.md), [consumption cleanup](03-consumption-cleanup.md) and [runtime validation](04-runtime-validation.md), together with existing authorization boundaries. Limitations remain separate from passing results.

## Requirements

- Stable V3 supports existing sessions and explicitly permitted guests only; external tokens are excluded.
- Accepted inputs, aliases and defaults remain unchanged except for the explicitly approved method redesign. Destructive GETs are removed from the stable V3 and first-party frontend surfaces before stability; migration impact includes creator one-time display and affected callers. Concrete replacement routes require inspection and are not selected here.
- Error-envelope consolidation covers V3 and first-party frontend APIs, including account, organization and domain surfaces, with the security and protocol constraints in [runtime validation](04-runtime-validation.md). V2 and Incoming remain unchanged absent an explicit separate decision.
- General API CORS is excluded. Only explicitly configured SSO endpoints receive CORS when their protocol requires it. Apple and SAML are examples for investigation, not automatic exceptions; redirects and form POSTs alone do not require CORS.
- Fresh mounted producer output passes both operation-schema and generated OpenAPI checks; missing output fails the gate. Historical fixtures remain regression evidence, not a substitute for fresh output.
- Fault coverage includes committed writes with lost acknowledgments, fully lost responses, process death, incomplete creations, required-registration failures, optional follow-up failures and fail-fast client response-validation failure without partial-handle retention.
- Cleanup evidence covers scheduled execution, tunable settings, discovery after process death, repeatability, at-most-once reveal and rollback safety without a fixed deadline or SLA.
- Passphrase coverage distinguishes empty and nonempty failed explicit reveals from metadata-only access, while preserving general rate limits for all of them.
- Authorization coverage includes cross-organization access, membership deletion, domain reassignment, missing identities, dependency outages and Incoming invalidation as unchanged regression behavior.
- Server/proxy method behavior, error/cache headers and any justified SSO CORS exception receive deployment-level validation.
- Every original ledger item retains an explicit disposition; passing samples do not close untested scenarios.

## Acceptance

Validation records identify the tested revision, environment, outcomes and omissions. Hosted CI is verified separately from local execution. Unresolved correctness and security blockers remain visible; approved direction is not proof that acceptance criteria pass.

## Exclusions and unresolved implementation details

External tokens (including PASETO), wider access, general API CORS, automatic mutation retries, a recovery service and a new complex cleanup framework are excluded. [AGENTS.md](../../../AGENTS.md) states: “Changes that widen access, including on error paths, require explicit operator approval.”

Implementation inspection resolves required registrations and persistence evidence, cleanup discovery/settings, exact envelope field mappings, replacement methods/routes and migration impact, operation schemas and non-revealing refresh, and any protocol-specific SSO CORS need. These details do not reopen the approved direction or authorize unrelated input/default changes.
