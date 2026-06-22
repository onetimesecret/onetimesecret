# OBS1 — `SessionDebugger` dumps full response headers (incl. `Set-Cookie`)

- **Severity:** Info (Low) — gated and off by default
- **Status:** Proposed fix (hardening + boot guard)
- **Affects default config?** **No** — disabled unless `DEBUG_SESSION` is set, and only mounted in the
  development environment.
- **Related:** Finding 06 #8. Sensitive-data-logging §6 (companion to the already-unwired
  `HeaderLoggerMiddleware`).
- **Primary files:** `lib/middleware/session_debugger.rb:98-103` (the `response_headers: headers` dump),
  `apps/web/core/application.rb:45-50` (mounted inside `Onetime.development?`, gated on `ENV['DEBUG_SESSION']`).

## Problem (recap)

When `DEBUG_SESSION` is truthy, `Rack::SessionDebugger` logs the **entire** response header hash at debug
level:

```ruby
# lib/middleware/session_debugger.rb:98-103
logger.debug 'Session debug complete',
  {
    status: status,
    duration: duration,
    response_headers: headers,    # <-- includes Set-Cookie (the session cookie value)
  }
```

This re-introduces the full `Set-Cookie` header — including the session cookie **value** — into the logs.
The middleware is otherwise careful: `log_cookies` (`:238-264`) deliberately discards the cookie
name/value (`:247`) and only logs the cookie *attributes*, and `log_session_state` obscures `email`
(`:145`). The wholesale `response_headers: headers` dump at `:102` defeats that care. It would also log
any `Authorization` or other sensitive response headers verbatim.

**Mitigating context (verified):** the middleware is mounted **only inside the `Onetime.development?`
block** — `apps/web/core/application.rb:45-50` — so with the production default (`RACK_ENV=production`,
which resolves to the `production` environment per `lib/onetime/class_methods.rb:409-415,432`) it is not
even added to the stack, regardless of `DEBUG_SESSION`. The risk is therefore confined to a developer who
sets `DEBUG_SESSION` in a dev environment. Still worth fixing: a stray session cookie value in dev logs
is needless exposure, and the current "dev-only" guarantee rests entirely on the `development?` wrapper
not being refactored away.

## Root cause

A debug convenience (dump everything) was added without a redaction filter, and the only thing preventing
production exposure is the placement of the `use` line inside the `development?` block — there is no
in-middleware guard that would survive a refactor.

## Prescribed resolution

### Implementation steps

1. **Redact sensitive headers before logging them.** In `session_debugger.rb` add a small allowlist/denylist
   helper and use it at `:102`:
   ```ruby
   SENSITIVE_RESPONSE_HEADERS = %w[set-cookie authorization www-authenticate proxy-authenticate].freeze

   def redact_headers(headers)
     headers.to_h.transform_keys(&:downcase).each_with_object({}) do |(k, v), out|
       out[k] = SENSITIVE_RESPONSE_HEADERS.include?(k) ? '[REDACTED]' : v
     end
   end
   ```
   ```ruby
   # :98-103 — replace `response_headers: headers` with:
   response_headers: redact_headers(headers),
   ```
   This keeps the diagnostic value (which headers were present, their non-sensitive values) without
   leaking the session cookie or auth tokens.

2. **Add a fail-closed boot guard so it can never run in production**, independent of where it is mounted.
   At the top of `SessionDebugger#initialize` (`:25-28`), refuse to enable in production even if
   `DEBUG_SESSION` is somehow set:
   ```ruby
   def initialize(app)
     @app = app
     wanted = ENV['DEBUG_SESSION'].to_s.match?(/^(true|1|yes)$/i)
     if wanted && Onetime.production?
       Onetime.li '[SessionDebugger] DEBUG_SESSION ignored in production'
       wanted = false
     end
     @enabled = wanted
   end
   ```
   This makes the guarantee intrinsic to the middleware rather than relying on the `application.rb:45`
   `development?` wrapper staying in place.

3. **Document the risk** in the middleware header comment (`:5-17`): note that `DEBUG_SESSION` logs
   session diagnostics, that sensitive headers are redacted, and that it is inert in production — so a
   future reader doesn't "helpfully" remove the guard or the redaction.

### Alternatives considered

- **Drop the `response_headers` line entirely:** simplest, and acceptable — but the redacted header list
  retains genuine debugging value (confirming `Content-Type`, cache headers, presence of `Set-Cookie`
  without its value). Redaction is a better balance than deletion.
- **Rely solely on the `development?` mount placement:** rejected — that is the *current* state and it is
  one refactor away from leaking. An in-middleware production guard is cheap insurance.
- **Gate on a log-level config instead of redacting:** doesn't help — anyone enabling `DEBUG_SESSION` is
  already opting into debug-level output; the cookie value must not be there in the first place.

## Test / verification

```ruby
# Spec: with DEBUG_SESSION enabled (dev), Set-Cookie is redacted in the response_headers dump.
# - Drive a request that sets a session cookie through the middleware.
# - Assert the emitted 'Session debug complete' log entry's response_headers['set-cookie'] == '[REDACTED]'
#   and that no raw 'rack.session=' value appears in any captured log line.

# Boot guard:
# - With RACK_ENV=production and DEBUG_SESSION=true, assert @enabled is false (middleware no-ops),
#   and that an info line notes DEBUG_SESSION was ignored.
```

Manual:
```bash
DEBUG_SESSION=true RACK_ENV=development bundle exec puma   # exercise login, grep logs:
#   -> 'response_headers' present, 'set-cookie' shows [REDACTED], no raw session value
RACK_ENV=production DEBUG_SESSION=true bundle exec puma     # -> debugger inert
```

## Effort & risk

- **Effort:** Trivial — a redaction helper, a four-line boot guard, and a comment.
- **Risk:** Very low. Affects only debug logging behavior; no production code path changes (the middleware
  is not mounted in production today and the guard makes that explicit).
