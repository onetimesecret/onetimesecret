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

The codebase contains multiple services with varying runtime requirements and dependency graphs. Test architecture decisions have been ad-hoc, creating inconsistency. The core tension: isolation vs. integration fidelity, and whether process separation reflects architecture or technical debt.

## Decision

**Test process boundaries mirror deployment process boundaries.**

Components running in the same process in production have tests capable of coexisting in a single test process. Components deployed as separate runtimes may be tested separately.

**Separate processes are legitimate when:**
- Different language runtimes
- Incompatible system-level dependencies
- Integration tests instantiate actual service processes
- Fundamentally different backing infrastructure

**Separate processes indicate debt when:**
- Tests fail together due to global state pollution or singleton contamination
- Unresolvable dependency version conflicts within a shared runtime
- Shared code initializes differently based on which test harness loads first
- Test fixtures collide due to assumed perpetual isolation

## Trade-offs

- **We lose**: The simplicity of "just run each service's tests separately"
- **We gain**: A diagnostic framework—when tests can't coexist, we know to investigate rather than accept fragmentation
- **Risk**: Judgment required to distinguish "incompatible dependencies" from "resolvable version conflict"

## Implementation Notes

See spec/README.md for operational details on running tests in different modes and services.
