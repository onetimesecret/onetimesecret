---
id: 002
status: accepted
date: 2025-10-10
title: ADR-002: Why a Custom Session Handler?
---

## Status
Accepted

## Date
2025-10-10

## Context

The application requires secure session management with Redis as the backend storage. Several options exist:

1. **Standard rack-session-redis** - Third-party gem from redis-store family
2. **Custom OnetimeSession** - In-house implementation using Familia ORM

Key constraints and factors:

- **Familia ORM**: The entire application uses Familia (v2.0.0) as its Redis abstraction layer for all models (Customer, Secret, Metadata, etc.)
- **Rack 3 Compatibility**: Application upgraded to Rack 3, requiring session handler compatibility
- **Maintenance**: Need for active maintenance and ability to fix issues quickly
- **Security**: HMAC verification, session tampering protection, timing-attack resistance
- **redis-rack status**: Last updated January 2020, redis-store family in maintenance-only mode

The decision was triggered by automated code review feedback (qodo-merge-pro on PR #1798) suggesting replacement with rack-session-redis for being "battle-tested."

**Reference**: https://github.com/onetimesecret/onetimesecret/pull/1798

## Decision

**We will continue using the custom OnetimeSession implementation** (`lib/onetime/minimal_session.rb`) rather than adopting rack-session-redis.

OnetimeSession extends `Rack::Session::Abstract::PersistedSecure` and provides:
- Redis storage via Familia::StringKey (consistent with application architecture)
- HMAC-based session integrity verification using SHA256
- Key derivation for different purposes (HMAC, encryption)
- Secure session ID generation (SecureRandom, 256-bit)
- Automatic TTL management via Familia's expiration features
- Graceful error handling with fallback to new sessions
- Forced cookie name (`onetime.session`) to prevent session fixation attacks

Implementation size: ~180 lines of well-documented, tested code.

## Consequences

### Positive

- **Architectural Consistency**: Single Redis client library (Familia) across entire stack; no mixing of redis gem and Familia abstractions
- **Active Maintenance**: Session handler maintained as part of codebase; can fix issues immediately without waiting for upstream gem updates
- **Modern Compatibility**: Built for Rack 3 with current best practices (2024)
- **Familia Integration**: Leverages connection pooling, logging, and TTL management from Familia
- **Security Control**: Full visibility into security implementation; timing-attack protection via `Rack::Utils.secure_compare`
- **Comprehensive Testing**: 20+ test cases in `try/unit/minimal_session_try.rb` covering edge cases, tampering, errors

### Negative

- **Custom Code Maintenance**: Team responsible for maintaining session handler code (though minimal at ~180 lines)
- **Not "Off-the-shelf"**: Requires code review from security perspective rather than relying on external audit history
- **Documentation Burden**: Must document behavior and security properties ourselves

### Neutral

- **Code Size**: +180 lines vs external dependency; minimal impact given comprehensive test coverage
- **Learning Curve**: New contributors must understand custom implementation, but well-documented with tests
- **Third-party Risk Trade-off**: Eliminated risk of unmaintained external dependency in exchange for internal maintenance responsibility

## Implementation Notes

### Development Status
As of 2025-10-10, the custom session handler implementation is in a feature branch and is being prepared for integration into the `develop` branch.
