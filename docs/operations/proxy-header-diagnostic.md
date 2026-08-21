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

Add a dedicated handler before the normal dynamic reverse-proxy handler. The
handler deletes each diagnostic field supplied by the client and replaces it
with Caddy's own observations.

```caddyfile
@proxy_header_debug path /api/colonel/system/proxy-headers
handle @proxy_header_debug {
    # A caller must not be able to forge Caddy's snapshots.
    header_up -X-Ots-Proxy-Debug-Peer
    header_up -X-Ots-Proxy-Debug-Host
    header_up -X-Ots-Proxy-Debug-Received-X-Forwarded-For
    header_up -X-Ots-Proxy-Debug-Received-Forwarded
    header_up -X-Ots-Proxy-Debug-Received-Apx-Incoming-Host

    # Values Caddy observed before it proxies the request.
    header_up X-Ots-Proxy-Debug-Peer {remote_host}
    header_up X-Ots-Proxy-Debug-Host {http.request.host}
    header_up X-Ots-Proxy-Debug-Received-X-Forwarded-For {http.request.header.X-Forwarded-For}
    header_up X-Ots-Proxy-Debug-Received-Forwarded {http.request.header.Forwarded}
    header_up X-Ots-Proxy-Debug-Received-Apx-Incoming-Host {http.request.header.Apx-Incoming-Host}

    reverse_proxy 127.0.0.1:7143
}
```

The exact upstream target should match the deployment's existing dynamic
`reverse_proxy` target. Restrict the route at the network edge as well when
possible.

## How to use it

Invoke it with curl using a live session cookie — no CSRF token is needed for
the GET:

```bash
curl -s https://admin.example.com/api/colonel/system/proxy-headers \
  -H 'Cookie: sess=<session-id>' | jq
```

Take the `sess` value from the browser after signing in as a colonel.

A `404` here is ambiguous by design: a rejected gate and a mistyped path look
identical to the client. Check the application log for a `NetworkRequirements`
warning ("Route network requirement not satisfied") to confirm which gate
refused the request.

1. From a signed-in Colonel session on an allowed admin host/network, send a
   request through the load balancer with a unique marker, for example
   `X-Forwarded-For: 203.0.113.77`.
2. Compare `caddy_received` with `request_headers`:
   - If Caddy's received snapshot contains the marker, the load balancer passed
     the client header to Caddy.
   - If the request header received by Rack differs from the snapshot, Caddy
     changed it while proxying.
3. Compare `caddy_received.x-ots-proxy-debug-peer` with
   `rack.remote_addr`. They may differ because the Rack IP-privacy middleware
   resolves and rewrites `REMOTE_ADDR` before the authentication strategy runs.
4. Check `rack.via_trusted_proxy`, `rack.client_ip`, and
   `rack.detected_host` to see the application's resulting trust decision.

The endpoint reports observations; it does not prove an upstream header is
trustworthy. A client can still choose any marker header. The result establishes
whether the load balancer sanitized that marker before Caddy received it.
