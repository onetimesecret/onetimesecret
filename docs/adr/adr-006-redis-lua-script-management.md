---
id: 006
status: accepted
title: ADR-006: Redis Lua Script Management Strategy
---

## Status
Accepted

## Date
2025-10-11

## Context

Redis Lua scripts can be managed in two ways:

1. **Built-in Management (redis-rb 4.0+)**: Use `redis.eval(script, ...)` with inline scripts. The client automatically:
   - Computes and caches SHA1 hashes per script content
   - Falls back from EVALSHA to EVAL on NOSCRIPT errors
   - Handles thread safety and connection pooling transparently

2. **Manual EVALSHA Management**: Pre-compute SHA1 hashes and explicitly manage script loading:
   ```ruby
   SCRIPT_SHA = Digest::SHA1.hexdigest(SCRIPT)
   redis.evalsha(SCRIPT_SHA, ...) rescue redis.eval(SCRIPT, ...)
   ```

The manual approach seems appealing for maximum cleanup/version control, but introduces complexity:

- **Connection Pool Challenges**: Each
 connection needs scripts loaded independently; server restarts clear all scripts
- **Minimal Memory Savings**: Old SHA1s persist in Redis memory until SCRIPT FLUSH (which clears all scripts)

The key insight: pre-computed SHA1s don't eliminate NOSCRIPT errors—they just move the problem. Server restarts, failovers, or new pool connections all require fallbacks to EVAL anyway.

## Decision

Use redis-rb's built-in `redis.eval(script, ...)` with inline scripts for Lua script execution.

The built-in approach handles all the edge cases automatically: SHA1 caching, NOSCRIPT fallbacks, connection pool synchronization, and server restart recovery. We get the same performance characteristics as manual management without maintaining our own fallback logic.

## Trade-offs

- **We lose**: Explicit control over script loading timing and ability to flush individual script versions
- **We gain**: Automatic handling of all Redis connection scenarios without custom error handling
- **Performance**: Negligible difference—first call per connection transmits the script, subsequent calls use cached SHA1
