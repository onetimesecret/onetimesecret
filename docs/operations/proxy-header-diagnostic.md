# Proxy header diagnostic

`GET /api/colonel/system/proxy-headers` is an operator diagnostic for
verifying what Caddy receives from an upstream load balancer and what the Rack
application sees after its proxy/IP middleware has run. Use it when setting up
or modifying an environment's proxy topology.

The route declares both application and network requirements:

- `auth=sessionauth role=colonel`
- `network=admin`

For this route, `network=admin` requires explicit, enforceable values for both
`ADMIN_ALLOWED_HOSTS` (`site.admin.allowed_hosts`) and `ADMIN_ALLOWED_CIDRS`
(`site.admin.allowed_cidrs`). If either setting is absent, disabled, invalid, or
does not admit the request, the endpoint returns `404`. The canonical-host
fallback used by ordinary Colonel routes does not satisfy this requirement.

`network=admin` is the **strict** of two tokens. Since #4332 there is also
`network=admin_if_configured`, carried by the 15 destructive colonel routes,
which enforces the same requirement only where the operator configured admin
isolation and otherwise falls through — a stock self-hosted install cannot
satisfy the strict token, and taking those routes away is not an option. This
route keeps the strict token deliberately: it is a read-only diagnostic that is
*supposed* to be absent unless both allowlists are set, which also makes it the
cheapest probe for which mode a deployment is in. See
[admin-network-isolation.md](admin-network-isolation.md#route-level-network-requirements).

`AdminNetworkIsolation` evaluates the host and CIDR gates before the Otto route
and its controller run. The endpoint returns only a fixed allowlist of
proxy-related fields; it does not dump arbitrary request headers.

## Required application configuration

Configure the admin hostname and the private network from which operators will
use the diagnostic:

```bash
ADMIN_ALLOWED_HOSTS=admin.example.com
ADMIN_ALLOWED_CIDRS=100.64.0.0/10
```

Use values for the actual deployment. See [Admin surface isolation](admin-network-isolation.md)
for trusted-proxy requirements, supported host values, and CIDR matching.

## Caddy configuration

Define the snippet below and import it at the site level alongside the normal
dynamic `reverse_proxy` snippet. It runs only for the diagnostic path and
replaces each diagnostic field supplied by the client with Caddy's own
observations.

```caddyfile
# Caddy snippet for GET /api/colonel/system/proxy-headers.
#
# Import at the SITE level, next to the reverse_proxy snippet:
#
#   secrets.example.com {
#     import onetime-proxy-debug
#     import onetime-proxy
#   }
#
# `route` falls through to the following handlers, so the request still goes
# through the ordinary reverse_proxy and all of its header_up rules. A separate
# handle with its own reverse_proxy would carry none of them and the endpoint's
# "did Caddy change this?" comparison would describe a handler no production
# request passes through.
#
# `request_header` rather than `header_up`: header_up is a reverse_proxy
# subdirective, unconditional by design, and accepts no matcher (a leading
# `@matcher` token is silently parsed as a regex-replace on a header named
# "@matcher"). request_header is the matcher-aware equivalent. It is Set
# semantics, so a client-supplied value is replaced, and its placeholders read
# the original request, so the Received-* values are captured before
# reverse_proxy's header_up rules strip them.
#
# NO explicit deletes. Caddy applies Add -> Set -> Delete regardless of source
# order, so a `-X` next to an `X {val}` deletes the value it just set and the
# endpoint reports nothing. An absent source resolves to "", not to the forged
# value. Verified on caddy v2.10.2.
#
# Only sent upstream for the diagnostic path. On other paths a client-supplied
# X-Ots-Proxy-Debug-* header passes through unchanged; the application ignores
# these headers everywhere except the diagnostic route.
(onetime-proxy-debug) {
  @proxy_header_debug path /api/colonel/system/proxy-headers
  # Placement in the site block is irrelevant: the Caddyfile adapter sorts
  # directives into a fixed order (header ... request_header ... route ...
  # reverse_proxy), not source order, so this runs before reverse_proxy
  # wherever it is imported. See
  # https://caddyserver.com/docs/caddyfile/directives#directive-order
  route @proxy_header_debug {
    # The values Caddy receives and makes available to the application.
    # Peer is the TCP peer after PROXY protocol unwrapping; client_ip is
    # Caddy's trusted_proxies verdict. They diverge exactly when the
    # trusted_proxies list has drifted.
    # TODO: Need to rewrite for multiple scenarios (with/without edge
    # proxy, with/without PROXY, with/without an LB).
    request_header X-Ots-Proxy-Debug-Peer      {remote_host}
    request_header X-Ots-Proxy-Debug-Client-IP {client_ip}
    request_header X-Ots-Proxy-Debug-Host      {http.request.host}

    # The values Caddy received and removes before the request reaches
    # the application.
    request_header X-Ots-Proxy-Debug-Received-X-Forwarded-For   {http.request.header.X-Forwarded-For}
    request_header X-Ots-Proxy-Debug-Received-X-Forwarded-Host  {http.request.header.X-Forwarded-Host}
    request_header X-Ots-Proxy-Debug-Received-X-Real-IP         {http.request.header.X-Real-IP}
    request_header X-Ots-Proxy-Debug-Received-X-Client-IP       {http.request.header.X-Client-IP}
    request_header X-Ots-Proxy-Debug-Received-Forwarded         {http.request.header.Forwarded}
    request_header X-Ots-Proxy-Debug-Received-Apx-Incoming-Host {http.request.header.Apx-Incoming-Host}
  }
}
```

The `reverse_proxy` snippet's upstream target should match the deployment's
existing dynamic target. Restrict the route at the network edge as well when
possible.

## How to use it

Invoke it with curl using a live session cookie — no CSRF token is needed for
the GET:

```bash
curl -s https://uk.onetimesecret.com/api/colonel/system/proxy-headers \
  -H 'Cookie: onetime.session=<session-id>' | jq
```

Take the `onetime.session` value from the browser after signing in as a colonel.

A `404` here is ambiguous by design: a rejected gate and a mistyped path look
identical to the client. Check the application log for a `NetworkRequirements`
warning ("Route network requirement not satisfied") to confirm which gate
refused the request.

1. From a signed-in Colonel session on an allowed admin host/network, send a
   request through the load balancer with a unique marker, for example
   `X-Forwarded-For: 203.0.113.77`.
2. Compare `caddy_received` with `request_headers`:
   - If `caddy_received` contains the marker, the load balancer passed
     the client header to Caddy.
   - If the request header received by Rack differs from `caddy_received`, Caddy
     changed it while proxying.
3. Compare `caddy_received.x-ots-proxy-debug-peer` with
   `rack.remote_addr`. They may differ because the Rack IP-privacy middleware
   resolves and rewrites `REMOTE_ADDR` before the authentication strategy runs.
4. Check `rack.via_trusted_proxy`, `rack.client_ip`, and
   `rack.detected_host` to see the application's resulting trust decision.
5. `request_headers.forwarded` and `request_headers.x-forwarded-host` are
   always empty: the application deletes both headers before any route runs.
   `rack.stripped_forwarded_headers` lists the ones it deleted (names only),
   so an empty entry there means the edge never sent the header.

The endpoint reports observations; it does not prove an upstream header is
trustworthy. A client can still choose any marker header. The result establishes
whether the load balancer sanitized that marker before Caddy received it.
