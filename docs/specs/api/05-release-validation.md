# 5. Release validation

Status: Proposed gate. These documents do not approve stable V3 promotion.

## Purpose and scope

Release evidence covers the preceding four stages and existing authorization boundaries, with limitations recorded separately from passing results.

## Requirements

- Fresh mounted producer output passes both operation-schema and generated OpenAPI checks; missing output fails the gate.
- Historical fixtures remain regression evidence, not a substitute for fresh output.
- Fault coverage includes committed writes with lost acknowledgments, process death and client response-validation failure.
- Authorization coverage includes cross-organization access, membership deletion, domain reassignment, missing identities, dependency outages and Incoming invalidation.
- Server/proxy method behavior and error/cache headers receive deployment-level validation.
- Every original ledger item retains an explicit disposition; passing samples do not close untested scenarios.

## Acceptance

Validation records identify the tested revision, environment, outcomes and omissions. Hosted CI is verified separately from local execution. Unresolved correctness and security blockers remain visible.

## Exclusions and open decisions

PASETO, wider access and broad wire-contract redesign are separate work. [AGENTS.md](../../../AGENTS.md) states: “Changes that widen access, including on error paths, require explicit operator approval.” Stable scope/error/default policies and empty-passphrase accounting require explicit decisions before corresponding behavior changes.
