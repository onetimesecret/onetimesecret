# Fork Safety: Connection Ownership Across Process Types

Two process types fork workers — Puma (web) and Sneakers (job consumers). Both delegate to `InitializerRegistry` for cleanup/reconnect, but they have different connection needs.

## Connection Roles

| Role | Owner | Used by | Created in |
|------|-------|---------|------------|
| **Publisher pool** (`$rmq_conn` / `$rmq_channel_pool`) | `SetupRabbitMQ` | Puma workers (enqueue jobs) | `setup_rabbitmq_connection` |
| **Consumer connections** | Sneakers/Bunny internals | Sneakers workers (process jobs) | Sneakers per-thread |

These must not coexist in a Sneakers worker. A publisher pool created after fork holds channels bound to the parent's TCP connection — stale in the child, leading to hangs or errors. `auto_reload_after_fork: false` on the ConnectionPool disables automatic recovery (intentionally — the registry manages lifecycle explicitly).

## Fork Lifecycle

```
WorkerCommand#call
  ├── ENV['SKIP_RABBITMQ_SETUP'] = '1'        ← process-level signal
  ├── boot_application! → OT.boot! :cli
  │     └── InitializerRegistry.run_all
  │           └── SetupRabbitMQ#execute → SKIP guard → returns early ($rmq_conn = nil)
  └── configure_sneakers
        └── hooks:
              before_fork  → registry.cleanup_before_fork
              after_fork   → registry.reconnect_after_fork
                               └── SetupRabbitMQ#reconnect → SKIP guard → return

Puma (no SKIP_RABBITMQ_SETUP):
  before_fork       → cleanup closes $rmq_conn, nils globals
  before_worker_boot → reconnect creates fresh publisher pool per worker
```

## Guard Placement

`SKIP_RABBITMQ_SETUP` is checked in both `SetupRabbitMQ#execute` and `#reconnect`, not in the registry or command layer. This keeps the "worker mode doesn't need a publisher pool" decision co-located with the publisher pool creation logic.

- **Registry** is connection-type-agnostic — it iterates all fork-sensitive initializers unconditionally.
- **WorkerCommand** sets the signal; **SetupRabbitMQ** interprets it. Clean separation.
- **`#cleanup`** needs no guard — if `execute` never created `$rmq_conn`, `cleanup` exits at `return unless conn&.open?`.

## Fork-Sensitive Initializers

Registered via `@phase = :fork_sensitive`. Each must implement both `cleanup` and `reconnect`. Run order is by name (TSort resolves dependencies first):

| Initializer | cleanup | reconnect | Env guard? |
|-------------|---------|-----------|------------|
| `SetupAuthDatabase` | Disconnects Sequel | No-op (lazy reconnect) | No |
| `SetupLoggers` | Flushes SemanticLogger | Reopens appenders | No |
| `SetupRabbitMQ` | Closes Bunny connection | Creates publisher pool | `SKIP_RABBITMQ_SETUP` |

## Adding a Fork-Sensitive Initializer

1. Set `@phase = :fork_sensitive` in the initializer
2. Implement `cleanup` (tear down connections/state inherited from parent)
3. Implement `reconnect` (establish fresh connections in child)
4. If the initializer should be skipped in certain process types, check an env var in both `execute` and `reconnect`
