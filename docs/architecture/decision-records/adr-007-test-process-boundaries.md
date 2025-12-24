---
id: 007
status: accepted
title: ADR-007: Test Process Boundaries in Multi-Service Architecture
---

## Status
Accepted

## Date
2025-12-22

## Context

The codebase contains multiple services with varying runtime requirements, deployment targets, and dependency graphs. As the service count grows, decisions about test architecture have been made ad-hoc, leading to inconsistency in how test suites are organized, executed, and maintained.

Key tensions:

1. **Isolation vs. Integration**: Running tests in separate processes provides isolation but obscures cross-service integration failures until CI or production.

2. **Speed vs. Fidelity**: Combining test suites into a single process reduces overhead but may require dependency compromises or introduce state leakage.

3. **Monorepo Expectations**: Co-locating code in a monorepo implies the ability to make atomic cross-service changes with unified validation. Test architectures that cannot leverage this co-location impose monorepo costs without proportional benefits.

4. **CI as Orchestrator**: Relying on CI to coordinate multi-process test execution is pragmatic but lengthens feedback cycles and complicates local debugging.

## Decision

**Test process boundaries will mirror deployment process boundaries.**

Components that run in the same process in production will have tests capable of coexisting in a single test process. Components deployed as separate runtimes may be tested in separate processes.

### Separate test processes are appropriate when:

- Services use different language runtimes
- Services have incompatible system-level dependencies (conflicting native library versions, mutually exclusive environment configurations)
- Integration tests instantiate actual service processes
- Services require fundamentally different backing infrastructure (different database engines, incompatible message broker versions)

### Separate test processes indicate technical debt when:

- Tests in the same runtime fail or behave incorrectly when run together due to global state pollution, import side effects, or singleton contamination
- Dependency version conflicts exist between services sharing a runtime that tooling cannot resolve
- Shared code initializes differently depending on which service's test harness loads it first
- Test databases or fixtures collide due to assumed perpetual isolation

### Requirements regardless of process separation:

1. A single command executes all tests across all services, invoking subprocesses as necessary
2. Changes to shared code trigger tests in all dependent services
3. Test infrastructure (fixtures, factories, service mocks) is shared where possible; duplication requires documented rationale
4. Cross-service coverage gaps are explicitly identified and either accepted with rationale or addressed through integration tests

### CI and local development:

- Full CI suite completes within 15 minutes for the common case
- Any individual service's tests can run locally without CI
- Shared library tests can run against all dependent services via a single command
- CI configuration is readable and locally reproducible
- Failing tests can be reproduced locally for debugging

## Consequences

### Positive

- Clear decision criteria reduce ambiguity when adding new services or restructuring existing ones
- Technical debt is distinguishable from legitimate architectural separation
- Monorepo benefits (atomic changes, shared tooling) remain achievable
- Feedback cycles stay short for single-service changes while full validation remains possible

### Negative

- Legitimate separation still incurs coordination overhead (shared fixtures, cross-service test triggers)
- The 15-minute CI budget may require investment in test parallelization or infrastructure
- Maintaining a unified test command across heterogeneous runtimes adds tooling complexity
- Developers must understand the distinction between "separate because architecture" and "separate because debt"

### Neutral

- This decision does not prescribe specific tooling; implementation varies by runtime and CI platform
- The boundary between "incompatible dependencies" and "resolvable version conflict" requires judgment
- Quarterly review of test architecture health metrics is implied but not mandated

## References

- Fowler, M. "Eradicating Non-Determinism in Tests"
- Clemson, T. "Testing Strategies in a Microservice Architecture"
- Internal: `/docs/testing-decisions.md` (operational quick-reference)
