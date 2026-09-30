# Reverse-proxy authority header

Which header the application reads to learn the host the visitor asked for,
who it accepts it from, and what it does not read. Tracked in #4384.

## The contract

The application reads the request authority from two places, in this order:

1. `X-Forwarded-Host`, when the request arrived through a trusted proxy and the
   header holds a single value.
2. `Host`.

Nothing else is a source. `Apx-Incoming-Host`, `X-Original-Host` and the
`host=` parameter of RFC 7239 `Forwarded` are not read.

This is implemented in one place, `Rack::DetectHost`
(`lib/middleware/detect_host.rb`). Its result is what the rest of the
application keys on: custom-domain classification, tenant SSO, sign-in gating,
emailed links, and the admin host gate.

### Who counts as a trusted proxy

- With `site.network.trusted_proxy` configured (`TRUSTED_PROXY_ENABLED=true`):
  a peer that passes it. A peer that fails it has `X-Forwarded-Host` removed
  before host detection runs.
- With it not configured (the default): a peer on a private or loopback
  address. This keeps a single-container install behind a local proxy working.

From any other peer `X-Forwarded-Host` is discarded, the request resolves on
`Host`, and the application logs a WARN starting
`[DetectHost] Discarding forwarded host headers (X-Forwarded-Host)`. If that
peer is your own reverse proxy, custom domains are resolving on `Host`;
configure `site.network.trusted_proxy`. With proxy trust configured the header
is removed earlier, so this WARN appears only in the unconfigured mode.

### A multi-valued `X-Forwarded-Host`

A comma-separated `X-Forwarded-Host` (or the header sent twice, which arrives
comma-joined) is not read. No value is picked from it. The request resolves on
`Host` and the application logs:

```text
[DetectHost] Ignoring X-Forwarded-Host with 2 values; the proxy must overwrite it with a single host. Falling back to Host
```

The request is still served; it is not answered with an error.

## What the proxy must do

The proxy in front of the application adapts whatever is upstream of it to the
contract:

- Overwrite `X-Forwarded-Host` with the host the browser asked for whenever
  something rewrites `Host`. Do not append to it and do not pass a
  client-supplied value through.
- Remove `Forwarded`, `Apx-Incoming-Host` and `X-Original-Host` before
  forwarding to the application.
- If an upstream layer carries the public host in its own header (Approximated
  uses `Apx-Incoming-Host`), copy that header into `X-Forwarded-Host`, and only
  for requests that come from that layer's address range.
- When `Host` already carries the public host, `X-Forwarded-Host` may be
  omitted. Overwriting it on every request is simpler and is what the example
  does.

`etc/examples/Caddyfile-example` does all of this in its `(onetime-proxy)`
snippet, including a commented block for Approximated.

nginx, with `Host` preserved:

```nginx
proxy_set_header Host              $host;
proxy_set_header X-Forwarded-Host  $host;
proxy_set_header Apx-Incoming-Host "";
proxy_set_header X-Original-Host   "";
proxy_set_header Forwarded         "";
```

## The admin host gate

`/colonel` and `/api/colonel` answer only on the hosts in
`site.admin.allowed_hosts` (the canonical host by default). The gate judges the
detected host, and it also looks at the headers the application does not read:
when `Apx-Incoming-Host`, `X-Original-Host`, or the first value of a
multi-valued `X-Forwarded-Host` names a host other than the detected one, both
admin surfaces return 404 for that request, from any peer. RFC 7239 `Forwarded`
is judged the same way for peers that are not a configured trusted proxy.

So a proxy that leaves one of those headers on the request does not change
which host is detected, but it can make the admin surfaces 404 where the header
and the detected host disagree. Removing the headers at the proxy avoids that.
See [admin-network-isolation.md](admin-network-isolation.md).

## Upgrading

Before this change the application also read `Apx-Incoming-Host` and
`X-Original-Host` (after `X-Forwarded-Host`, before `Host`), and took the first
value of a comma-separated `X-Forwarded-Host`. Check your proxy before
upgrading if any of these apply.

**Your proxy rewrites `Host` and forwards the public host only in
`Apx-Incoming-Host` or `X-Original-Host`.** After upgrading, those requests
resolve on `Host`: custom domains are served as the canonical site, tenant SSO
and sign-in settings for the domain do not apply, and emailed links name the
canonical host. Change the proxy to send `X-Forwarded-Host` first (the previous
release already reads it, ahead of the other two), then upgrade.

**You copied the previous `etc/examples/Caddyfile-example`.** It removed
`X-Forwarded-Host` and set `X-Original-Host` to the request host. With `Host`
preserved, as that example does, detection is unchanged. Update to the new
snippet anyway: a leftover `X-Original-Host` is one of the headers the admin
gate compares, and the new snippet is what the Approximated block builds on.

**You run chained proxies that append to `X-Forwarded-Host`.** Apache
`mod_proxy` adds its value to an `X-Forwarded-Host` that is already present, so
an Apache instance behind another proxy produces a comma-separated header. The
first value used to be selected; now the request resolves on `Host`, with the
WARN shown above. Have the proxy nearest the application overwrite the header
with a single host, or preserve `Host` end to end.

**You use the colonel proxy diagnostic**
([proxy-header-diagnostic.md](proxy-header-diagnostic.md)). Its
`request_headers` section no longer has an `apx-incoming-host` entry.
`caddy_received` still reports what the edge received.

To check a deployment after upgrading: request a custom domain and confirm the
response is branded for it, and search the application log for the two
`[DetectHost]` WARN lines above.
