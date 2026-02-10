# Auth DB: Console Debugging

Connection is lazy — no DB call until first query. See `Auth::Database::LazyConnection` in `database.rb`.

## Config

```ruby
Onetime.auth_config.full_enabled?   # false means DB is never connected
Onetime.auth_config.database_url
Onetime.auth_config.mode
```

## Connect and test

```ruby
db = Auth::Database.connection   # nil in simple mode
Auth::Database.connected?        # has the lazy proxy connected yet?

db.__connect__!                  # force TCP/socket connection (errors surface here)
db.test_connection
db[:accounts].count
```

## Inspect

```ruby
db.adapter_scheme   #=> :sqlite or :postgres
db.opts             #=> connection hash
db.tables
db.views
db.schema(:accounts)
db.loggers          # SQL logging is :trace by default
```

## Multi-host PostgreSQL

```ruby
Auth::Database.parse_postgres_multihost_url(Onetime.auth_config.database_url)
```

## Reset

```ruby
Auth::Database.reset_connection!
db = Auth::Database.connection
db.__connect__!
```
