---
id: "010"
status: proposed
title: "ADR-010: Error Handling at Layer Boundaries"
---

## Status

Proposed

## Date

2026-05-24

## Context

Recent PR reviews surfaced disagreement over whether predicate methods and read paths should raise or return a safe default when a record is missing. Rack handlers have no supervisor — an unhandled exception is a 500, not a retry. Ruby `?` methods are expected to return a boolean. At the same time, integrity violations on writes must not be accepted silently.

## Decision

**Error handling is partitioned by layer.**

- **Write and integrity boundaries** (`create!`, `save!`, migrations): raise. Bad writes must not be accepted silently.
- **Boot paths** (config, required env, dependency wiring): raise. Bad config dies at startup, not per-request.
- **Read paths in hot code** (Rack handlers, predicate methods, view helpers): return a safe default, emit a metric or structured log, rely on operator alerting. Predicate methods (`?`) return a boolean — never raise.

This mirrors the split mature OSS converges on: Rails (`find` raises, `find_by` returns nil), Django (`ImproperlyConfigured` at boot, lenient at runtime), Kubernetes controllers (reconcile-and-requeue), OTP (let-it-crash assumes a supervisor — Rack does not).

## Trade-offs

- **We lose**: Immediate stack traces at pathological state. Debugging missing records at read time means correlating logs and metrics, not reading a backtrace.
- **We gain**: Graceful degradation in production. Predicate methods behave per Ruby convention.
- **Risk**: Monitoring is load-bearing. Read-path counters and structured warnings must be wired to alerting — a degraded state with no alert is worse than a 500.
