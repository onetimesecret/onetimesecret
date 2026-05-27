# lib/onetime/initializers/README.md
---

Each file here is a single boot step — a subclass of `Onetime::Boot::Initializer` that runs once during application startup to configure a subsystem (loggers, database connections, locales, RabbitMQ, Sentry, etc.) or to set runtime state on `Onetime::Runtime`.

Initializers are ordered by declarative dependency, not file load order. Each class declares:

- `@provides` — capability tokens this initializer makes available (e.g. `:logging`, `:database`).
- `@depends_on` — tokens that must be satisfied first; the registry topologically sorts the graph.
- `@phase` — `:fork_sensitive` for anything holding sockets/threads that won't survive fork (logging, database, RabbitMQ); such classes implement `cleanup` and `reconnect` for Puma/Sneakers fork hooks.
- `@optional` — when true, failure logs an error instead of aborting boot.

The `execute(context)` method does the work. Don't perform work at file-load time and don't call other initializers directly — express ordering through `@depends_on`.

## Logging

Logging conventions in `lib/onetime/initializers/`

**Logger selection** — prefer a named logger:
- `OT.boot_logger` — default for initializer code (boot phase). See `configure_familia.rb`, `detect_legacy_data_and_warn.rb`, `print_log_banner.rb`, `load_locales.rb`, `setup_diagnostics.rb`.
- Category loggers when topic is specific: `Onetime.familia_logger` (database/Familia), `Onetime.bunny_logger` (RabbitMQ), or a local `app_logger` from the cached-logger registry (`configure_trusted_proxy.rb`, `configure_domains.rb`).
- **Deprecated**: `OT.ld` / `OT.li` / `OT.le` / `OT.info`. These global helpers infer the category from the caller's file path (`class_methods.rb:291`) — files under `lib/onetime/initializers/` resolve to the `Boot` category, the same one `OT.boot_logger` returns. Prefer the named logger: it's explicit at the call site, avoids the `caller_locations` stack walk, and won't silently re-route if a file moves out of `/initializers/`. It also lets an initializer log to a non-Boot category (e.g. Familia, Bunny) where path inference would still pick Boot. Existing call sites (`check_redis_url`, `setup_i18n`, `setup_connection_pool`, `load_fortunes`) should migrate to `OT.boot_logger` or the appropriate category logger.
- Never bare `puts` / `warn` except in `cleanup`/`reconnect` rescue paths where the logger itself may be unavailable (see `setup_loggers.rb:84`).

**Message format**: short, fixed message string; pass context as a structured payload, not interpolated into the message.

```ruby
OT.boot_logger.info 'Configure Familia URI', uri: uri
OT.boot_logger.error 'Legacy data detection failed', exception: ex
```

The category prints from the logger name; no `[tag]` prefix needed. Older call sites use a `[tag] message` prefix style — leave them alone but don't add new ones.

**Level discipline**:
- `debug` — routine progress (`Loaded X`, `Scanning…`, `Configured Y`). Backtraces always go at `debug` (`ex.backtrace.join("\n")`).
- `info` — single-shot lifecycle milestones (banner load, fork cleanup, scan-complete summary).
- `warn` — recoverable config issues (`CHANGEME` password, invalid CIDR).
- `error` — failures; usually paired with a `debug` line carrying the backtrace.
- `fatal` — only for boot-blocking misconfiguration, followed by `raise Onetime::Problem`.

**Categories** are fixed in `setup_loggers.rb:34`: App, Auth, Billing, Boot, Bunny, Familia, HTTP, Jobs, Otto, Rhales, Scheduler, Secret, Sequel, Session, Workers. Each gets a `DEBUG_<NAME>` env override.
