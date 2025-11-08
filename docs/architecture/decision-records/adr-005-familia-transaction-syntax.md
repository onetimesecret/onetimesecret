---
id: 005
status: accepted
title: ADR-005: Familia Transaction Block Syntax (Yield Connection)
---

## Status
Accepted

## Date
2025-10-11

## Context

Familia (Ruby ORM for Redis/Valkey) recently added transaction/pipeline support across four usage levels. The implementation currently yields the Redis connection to blocks.

**Current Pattern:**
```ruby
stringkey.transaction do |conn|
  conn.set(stringkey.dbkey, data)
  conn.expire(stringkey.dbkey, 3600)
end
```

**Proposed Alternative:**
```ruby
stringkey.transaction do |instance|
  instance.set(data)
  instance.expire(3600)
end
```

**Why Alternative Doesn't Work:**
- **Cannot operate on multiple DataTypes in single transaction**
- Global level `Familia.transaction` has no instance to yield
- Would require wrapper methods for 200+ Redis commands on every DataType

## Decision

**Maintain yielding the Redis connection** for all transaction blocks across all four usage levels.
