# docs/specs/testing-lanes/valkey-max-dbsize.md
---



## Answer

**Maximum number of databases:** There is no hard-coded upper limit. The `databases` directive in `redis.conf` / `valkey.conf` sets `server.dbnum`, and you can set it to any integer. The default is 16. [^5] [^6]

**It is NOT lazy-loaded — it is a pre-allocated array.** During `initServer()`, Redis/Valkey allocates a contiguous array of `redisDb` structs via `zmalloc()` and stores it in `server.db`. The array length is exactly `server.dbnum`. [^3] [^4]

From the DeepWiki source analysis:

> `server.db` — `redisDb *`. Array of logical databases (default 16). Each logical database is a `redisDb` struct containing `db->keys` (a kvstore for data) and `db->expires` (an estore for expiration metadata). [^4]

So your intuition is correct: **setting `databases 1001` means 1001 `redisDb` structs are allocated at startup, even if you only use db 0.** The per-database overhead is "linear relative to the number of databases used, not keys" — i.e., each slot in the array costs a fixed amount of memory regardless of whether it holds any keys. [^1]

### What's actually in each `redisDb` struct

Each element of the array contains (at minimum):
- A pointer to the keyspace (`kvstore` in Redis 8.x / Valkey, a dict in older versions)
- A pointer to the expires table (`estore` / dict)
- An `id` field
- Blocking keys / watched keys structures (in older versions; some have been refactored)

The `kvstore`/`estore` themselves are initialized but **empty** (no hash tables for actual keys yet — the internal dict hash table is allocated lazily on first insert). So an *unused* database slot costs roughly the size of the `redisDb` struct plus whatever the kvstore/estore constructors pre-allocate (typically a small metadata structure, not a full hash table of slots).

### Practical magnitude

- A `redisDb` struct is on the order of ~100–200 bytes (varies by version; Redis 8.x's `kvstore` adds some metadata).
- At `databases 1001` you'd pay roughly **~100–300 KB** of always-resident overhead for the 1000 unused slots. Negligible on any real server, but not literally zero.
- The memory is **O(dbnum), not O(dbnum × keys)** — the cost is fixed per database, independent of how many keys live in it. [^1]

### Cluster mode caveat

In cluster mode (both Redis OSS cluster and Valkey 8.x cluster), **only db 0 is permitted** — `SELECT` is disabled. So the `databases` setting only matters in standalone/replica mode. Valkey 9.0 is changing this to allow numbered databases in cluster mode, which is what the "10 million databases" PR (#1609) work is about — that effort specifically addresses reducing per-database overhead so very large database counts become feasible. [^2] [^1]

### Summary

| Scenario | What happens in memory |
|---|---|
| `databases 1`, use db 0 | One `redisDb` allocated, one kvstore initialized |
| `databases 1001`, use only db 0 | **1001 `redisDb` structs allocated at startup**; 1000 of them sit idle with empty kvstores. Cost ≈ 1000 × (struct size). Not lazy. |
| Cluster mode (Redis/Valkey 8) | `databases` ignored; effectively db 0 only |

So: not arbitrarily free, but the cost is small and linear in `dbnum`. Setting it to 1001 won't materially hurt you, but it's also not "the same as setting it to 1" — you do pay for the pre-allocated array.

**References**

[^1]: [Valkey · Numbered Databases in Valkey 9.0](https://valkey.io/blog/numbered-databases/) (30%)
[^2]: [Valkey 9.0: innovation, features, and improvements.](https://valkey.io/blog/introducing-valkey-9/) (28%)
[^3]: [Understanding Redis Source Code](https://wangziqi2013.github.io/article/2023/02/12/redis-notes.html) (15%)
[^4]: [Redis Core | redis/redis | DeepWiki](https://deepwiki.com/redis/redis/2-redis-core) (14%)
[^5]: [Maximum number of databases in redis](https://stackoverflow.com/questions/36735236/maximum-number-of-databases-in-redis) (13%)
[^6]: [Valkey Command · SELECT](https://valkey.io/commands/select/) (0%)
