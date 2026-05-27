# Verifying the Feedback Rate Limit End-to-End

## Overview

`POST /api/v3/feedback` is rate-limited per client IP by
`Onetime::Security::FeedbackRateLimiter`. Unit tryouts exercise the
module and the logic class in isolation, but the full HTTP path —
controller → auth strategy (`NoAuthStrategy.build_metadata`) →
`Rack::Request#ip` → logic → Redis lockout key → JSON error
envelope — only runs against a live server. Use this runbook before
shipping any change that touches the feedback endpoint, the
`FeedbackRateLimiter` module, the auth strategies' metadata
construction, or the trusted-proxy configuration.

## Prerequisites

- Local Redis reachable at the configured port (default `2121`).
- App running via `bin/dev` (or `bundle exec puma -p 3000` for an
  isolated server). Use `curl http://localhost:7143/api/v3/status`
  to confirm the port; adjust the examples below if your dev port
  differs.
- `redis-cli -p 2121` available for inspecting rate-limit keys.

## Golden path: ten accepted, eleventh rejected

```bash
PORT=7143  # adjust to your dev server's port

for i in $(seq 1 11); do
  printf "Request %2d → " "$i"
  curl -sS -o /tmp/feedback-resp.json \
       -w "%{http_code}\n" \
       -X POST "http://localhost:${PORT}/api/v3/feedback" \
       -H 'Content-Type: application/json' \
       -d '{"msg":"smoke test","tz":"UTC","version":"dev"}'
done
cat /tmp/feedback-resp.json | jq .
```

Expected:

- Requests 1–10: `200`
- Request 11: `429` (or whatever status the edge maps
  `Onetime::LimitExceeded` to — confirm via the response body)
- Final body contains `"error_type":"LimitExceeded"`, a positive
  `retry_after` (≤ 3600), and `"max_attempts":10`.

## Inspect Redis state

```bash
redis-cli -p 2121 KEYS 'feedback:*'
# Expect a single feedback:locked:<ip> key after the 10th request.

redis-cli -p 2121 TTL "feedback:locked:127.0.0.1"
# Expect ≤ 3600.
```

Note: `<ip>` is whatever `Rack::Request#ip` resolves to. On a vanilla
local server that's `127.0.0.1`. If you're reproducing a
Cloudflare / proxy scenario, see "Proxy-aware run" below.

## Reset between runs

```bash
redis-cli -p 2121 DEL feedback:locked:127.0.0.1 feedback:submissions:127.0.0.1
```

Or, from a console (`bundle exec bin/console`):

```ruby
class R; include Onetime::Security::FeedbackRateLimiter; end
R.new.clear_feedback_rate_limit!('127.0.0.1')
```

## Proxy-aware run

To verify the trusted-proxy → `Rack::Request#ip` chain (e.g. after
changing `build_metadata`), spoof the forwarding header and confirm
the lockout keys off the *client* IP, not the loopback peer:

```bash
# With TRUSTED_PROXY_ENABLED=true and a CIDR that covers loopback
# (e.g. TRUSTED_PROXY_CIDRS=127.0.0.0/8), this XFF should be honored:
for i in $(seq 1 11); do
  curl -sS -o /dev/null -w "%{http_code}\n" \
       -X POST "http://localhost:${PORT}/api/v3/feedback" \
       -H 'Content-Type: application/json' \
       -H 'X-Forwarded-For: 203.0.113.42' \
       -d '{"msg":"proxy test"}'
done

redis-cli -p 2121 KEYS 'feedback:*'
# Expect feedback:locked:203.0.113.42 (the spoofed client IP),
# NOT feedback:locked:127.0.0.1.
```

If you see `feedback:locked:127.0.0.1` instead, either
`trusted_proxy.enabled` is false, the CIDR doesn't cover the peer,
or `build_metadata` is still reading `REMOTE_ADDR` directly.

## Negative checks

- **Empty body:** `-d '{}'` should return a form error ("You can be
  more original than that!") and *not* increment the counter
  (record happens after `Feedback.add`).
- **Missing IP:** simulate by routing through a misconfigured proxy
  that strips `REMOTE_ADDR`; the limiter should silently no-op
  rather than raise. (Hard to reproduce locally; trust the
  `client_ip returns nil` unit case.)

## Cleanup

```bash
redis-cli -p 2121 --scan --pattern 'feedback:*' | xargs -r redis-cli -p 2121 DEL
```
