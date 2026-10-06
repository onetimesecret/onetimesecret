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

### A value with userinfo

A value with an `@` in it (`user:pw@secrets.example.com`,
`https://user@secrets.example.com/`) names no host, in `X-Forwarded-Host` or
in `Host`. A request authority has no userinfo.

When a trusted proxy sends such a value as the single `X-Forwarded-Host`, no
host is detected for the request and the application does not fall back to
`Host`. The request is handled like one with an IP-literal `Host`: it does not
classify as a served host, and both admin surfaces return 404. The application
logs:

```text
[DetectHost] Refusing X-Forwarded-Host with userinfo ('@') in it; no host is detected for this request. The proxy must send a bare host or host:port
```

This differs from the other unusable values (an IP literal, `localhost`, a
malformed name), which are skipped in favour of `Host`. `user:pw@host` was
previously read as the host `user`, which is never a served host, so falling
back to `Host` would have served and admitted requests that were refused.

## What the proxy must do

The proxy in front of the application adapts whatever is upstream of it to the
contract:

- Overwrite `X-Forwarded-Host` with the host the browser asked for whenever
  something rewrites `Host`. Do not append to it and do not pass a
  client-supplied value through.
- Remove `Forwarded`, `Apx-Incoming-Host` and `X-Original-Host` before
  forwarding to the application.
- Overwrite `X-Forwarded-Port` with the public port, or remove it. With `Host`
  preserved the port is already in `Host` and the header is not needed.
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
proxy_set_header X-Forwarded-Port  "";
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
is judged the same way for peers that are not a configured trusted proxy. A
value with userinfo (`user:pw@host`) in one of those headers names no host and
is judged as a host that disagrees.

So a proxy that leaves one of those headers on the request does not change
which host is detected, but it can make the admin surfaces 404 where the header
and the detected host disagree. Removing the headers at the proxy avoids that.
See [admin-network-isolation.md](admin-network-isolation.md).

## Rack's own host (`site.network.public_host_rewrite`)

The detected host is what the application keys on, but it is not what
`Rack::Request#host` returns. Behind a proxy that rewrites `Host` to the origin
target, Rack's host is the origin target: `X-Forwarded-Host` is removed from
the request once it has been read, so nothing downstream reads it a second
time. Application code reads the resolved host. Code that reads the Rack host
directly, including mounted gems, gets the origin target.

`site.network.public_host_rewrite` (`PUBLIC_HOST_REWRITE=true`, default off)
closes that gap. When it is on, `Onetime::Middleware::PublicHostRewrite` sets
`Host` to the detected host for a request that:

- classified as a canonical host, a subdomain or peer of one, or a registered
  custom domain, and
- was detected on a valid hostname that is the request's display domain, and
- does not already carry that host in `Host`.

Every other request is left as received. That includes an unregistered host, a
custom domain whose record could not be read, a request the application could
not detect a host for (`localhost`, an IP literal), and any request while the
custom-domains feature is off unless it resolved to `site.host` itself.

Details:

- The rewritten `Host` carries the public port the trusted proxy sent with the
  single-valued `X-Forwarded-Host` that host detection selected. The port is
  read from one of two places, in this order:

  1. `X-Forwarded-Host` itself, when it is a plain `hostname:port` authority.
     `X-Forwarded-Host: secrets.example.com:8443` produces
     `Host: secrets.example.com:8443`.
  2. `X-Forwarded-Port`, when `X-Forwarded-Host` is a bare hostname.
     `X-Forwarded-Host: secrets.example.com` with `X-Forwarded-Port: 8443`
     produces the same `Host`. This is the usual nginx setup
     (`X-Forwarded-Host $host` drops the port).

  The port must be one number from 1 through 65535. A list of ports
  (`8443, 443`) is not picked from, and a port written in `X-Forwarded-Host`
  that is out of range is not replaced by `X-Forwarded-Port`; in both cases no
  port is written. The default port of the request's scheme (443 for https,
  80 for http) is left out of `Host`.
- With the port in `Host`, `Rack::Request#port` and `#base_url` agree on a
  rewritten request. Rack's `base_url` reads the authority alone, so without
  this a port sent only in `X-Forwarded-Port` would appear in `#port` and not
  in `#base_url`.
- No port is copied from the received `Host`, which may name the origin hop.
  A port configured in `site.host` still applies to auth URLs built for the
  canonical host.
- `X-Forwarded-Port` is read from a trusted proxy only, on the same verdict as
  `X-Forwarded-Host`. From any other peer it is removed before the
  applications run, whether or not this setting is on, so a direct client
  cannot choose the port in a generated URL.
- From a trusted proxy it is kept only when it is one port from 1 through
  65535. Anything else (`0`, `65536`, `abc`, a list such as `8443, 443`) is
  removed, also whether or not this setting is on: Rack would otherwise turn
  it into a number and use it.
- A trusted proxy's `X-Forwarded-Proto: ws` is read as `http`, and `wss` as
  `https`, whether or not this setting is on. The same applies to
  `X-Forwarded-Scheme` and to the `proto=` of `Forwarded` when that family is
  the one read. Rack accepts both values and has no default port for either,
  so with `wss` and no public port it reported the origin hop's port
  (`SERVER_PORT`) as the request port while the request URL carried none. The
  application serves HTTP only; send `https` or `http`.
- On a rewritten request `X-Forwarded-Port` is removed once the port has been
  written into `Host`, so `Host` is the only place a port is read from.
- `X-Forwarded-Port` is under the same contract as `X-Forwarded-Host`: the
  proxy must overwrite it with the public port, or remove it. A proxy that
  passes a client's value through lets the client choose the port in generated
  URLs. Caddy's `reverse_proxy` and nginx's `proxy_pass` both pass it through
  unless told otherwise; the examples here remove it. A proxy that sends its
  own listening port instead of the public one (for example port 80 behind a
  TLS-terminating load balancer) produces URLs on that port.
- A `Host` that arrives doubled (`Host: a, a`) and resolves to a served host is
  replaced by that host.
- The `Host` as received is kept in the Rack env as
  `onetime.original_http_host` on a rewritten request. The colonel proxy
  diagnostic reports it as `request_headers.host`.
- The `Origin` check on unsafe requests (`Rack::Protection::HttpOrigin`)
  compares `Origin` with the request's own scheme, host and port, so on a
  rewritten request it compares against the public authority instead of the
  origin target. Compared with the setting off, through the same proxy:
  - an `Origin` naming the origin target is refused (it was admitted);
  - `https://{public host}:{port}` is admitted when the proxy sent that
    non-default public port (it was refused: only the port-less
    `https://{public host}` matched);
  - `http://{public host}` is admitted on a request the application sees as
    http (it was refused). This applies when the proxy does not forward the
    scheme and `ASSUME_HTTPS` is off; forward `X-Forwarded-Proto: https` or
    set `ASSUME_HTTPS=true` so the request is https.

  A proxy that preserves `Host` gets the same three results in either
  setting. A foreign `Origin` is refused in every case, and the CSRF token
  check still applies.
- An `Origin` naming a host that is not a canonical host, a subdomain of
  one, or a registered custom domain is refused behind a proxy that rewrites
  `Host`, whether or not this setting is on (it used to be admitted when it
  matched the detected host). A registered custom domain whose record could
  not be read is still admitted, so the application's own refusal answers
  the request. A proxy that preserves `Host` is unchanged: the request's own
  authority already matches that `Origin`.
- The admin host gate runs before the rewrite and is unchanged by it.
- A proxy that preserves `Host` needs none of this: the request already
  carries the public host and nothing is rewritten.

With the setting on, a request through a Host-rewriting proxy reaches the
mounted applications with the same host a Host-preserving proxy would have
delivered. `X-Forwarded-Host` is still accepted from a trusted proxy only.

## Authentication URL configuration

Authentication email links and SSO callback URLs require a resolved origin from
one of these sources, in order:

1. A verified custom domain resolved for the request.
2. The request's host when it belongs to the configured canonical set.
3. The configured `site.host` fallback.

If none resolves, URL generation fails instead of using the request's raw
`Host`. This also applies when `site.host` is missing or blank. An unverified
tenant or an unregistered host cannot become an authentication-link destination
just because it reached the server.

A password-reset POST in that configuration returns a generic HTTP 500 before
account lookup, reset-key changes, or email publication. Request rate limiting
still runs first and may return its usual HTTP 429. Existing reset keys are not
changed by the missing-origin refusal.

Configure `site.host` with the public canonical authority, including its port
when needed, or complete verification of the request's custom domain. A verified
tenant or a configured canonical request host still resolves without the
`site.host` fallback. Do not work around the failure by trusting arbitrary
incoming host headers.

## Upgrading

**You use SAML behind a Host-rewriting proxy.** Deploy the callback-scope fix
on all workers with `PUBLIC_HOST_REWRITE` off, then enable rewriting. The fix
binds staged callbacks to the received authority, so enabling the setting
between a callback POST and its follow-up GET does not change that scope.

If rewriting is already enabled on workers without this fix, drain in-flight
SAML callbacks before changing the setting or mixing worker versions. Use a
maintenance window to stop new SAML sign-ins while existing callbacks finish;
staged handles expire after 120 seconds. Otherwise, affected users must restart
sign-in. Old workers with rewriting enabled stage callbacks under the rewritten
public authority, which fixed workers reject. Those scopes are not migrated or
retried under an alternate scope.

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
