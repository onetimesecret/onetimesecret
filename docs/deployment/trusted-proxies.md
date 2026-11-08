---
# docs/deployment/trusted-proxies.md
---
# Trusted proxies: deployment considerations

This guide is for operators deploying OneTimeSecret behind a reverse proxy,
ingress, or load balancer, especially when serving custom domains. It records
recommended deployment checks, not a security certification or evidence that
an adversarial test suite has passed.

The application can defend against many external misconfigurations, but not
all. The security boundary is which peers may supply public request metadata,
which domains the application accepts, and whether downstream components use
that decision consistently.

## Configure the trust boundary

- **Declare proxy trust explicitly.** Configure `site.network.trusted_proxy`
  with the proxy's own address ranges, not an entire shared private network.
  Follow the configuration guidance in
  [Admin surface isolation](../operations/admin-network-isolation.md#behind-a-reverse-proxy-or-load-balancer--required-for-both-gates).
- **Restrict origin access.** Use network controls so only intended proxies
  and authorized operational clients can reach the origin. Check both public
  ingress and access from other workloads on private networks.
- **Do not treat a private address as proof of authorization.** Currently,
  `Rack::DetectHost.from_trusted_proxy?` uses an explicit
  `otto.via_trusted_proxy` verdict when present; without it, it falls back to
  trusting private or loopback peers. Another workload that can reach the
  origin from such an address can therefore supply forwarded host metadata.
- **A proxy on a public address must be declared.** Forwarded host, port and
  scheme headers are all read on that one verdict. `X-Forwarded-Proto`,
  `X-Forwarded-Scheme` and `X-Forwarded-SSL` from a peer that is not trusted
  are removed, and the request keeps the scheme of the connection to the
  origin. If the proxy terminates TLS and reaches the origin from a public
  address without being listed in `site.network.trusted_proxy`, the
  application sees `http`: a `Secure` session cookie is not written and
  request-derived URLs use `http`. The `[Session] cookie NOT written` log
  line names the removed headers in `untrusted_scheme_headers`.
- **Send `https` or `http` as the forwarded scheme.** A trusted proxy's
  `X-Forwarded-Proto` or `X-Forwarded-Scheme` of `wss` is read as `https`, and
  `ws` as `http`. The application serves HTTP only, and Rack has no default
  port for the WebSocket schemes: left as sent, the request port became the
  port of the connection to the origin.
- **Review every hop.** For a CDN, load balancer, and ingress chain, identify
  where client-supplied metadata is discarded and which hop supplies the
  values the application consumes. Recheck trust ranges when topology changes.

## Client IP resolution

With `site.network.trusted_proxy` enabled in `filter` mode, the client IP is
read from `X-Forwarded-For` from the right: the hop nearest the application
first, skipping every entry that is a trusted proxy, stopping at the first
that is not. Entries to the left of that one are never selected. The private,
loopback and link-local ranges are always trusted; a hop with a public address
(a CDN edge, a cloud load balancer) is trusted only when it is listed in
`trusted_proxy.cidrs`. The walk cannot tell a trusted-range address that
belongs to a proxy from one that belongs to the client, which is what the
"private clients" item below is about.

- **List every hop.** A proxy between the client and the application that is
  not in the trusted set is the client IP for every request through it.
  Per-IP rate limits and bans collapse onto that address, and the admin
  network gate judges it. Include CDN egress ranges and load balancer
  addresses, and recheck the list when the topology changes.
- **Have each proxy append.** Each hop should append the address it received
  the request from to `X-Forwarded-For` (nginx:
  `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`), or replace
  a client-supplied value. An edge that
  overwrites the header with the single address it resolved is also correct,
  and with private clients it is required (next item). A proxy that sets only
  `X-Real-IP` must also write `X-Forwarded-For`: `X-Real-IP` and `X-Client-IP`
  are read only when `X-Forwarded-For` is absent or blank.
- **Private clients need the overwrite.** Appending keeps a client-supplied
  entry out only because the client's own appended address is untrusted and
  stops the walk. A client whose address is in a trusted range is skipped as
  a hop instead: a client at `192.168.1.50` that sends
  `X-Forwarded-For: 203.0.113.99` through an appending proxy produces
  `203.0.113.99, 192.168.1.50`, and the walk selects `203.0.113.99`, a value
  the client chose, which then steers every per-IP rate limit, IP bans and
  the audit trail. Where clients have RFC1918, loopback or link-local
  addresses (a LAN, a VPN, a corporate network) the edge must overwrite
  `X-Forwarded-For` with the one address it resolved (Caddy:
  `header_up X-Forwarded-For {client_ip}`; nginx:
  `proxy_set_header X-Forwarded-For $remote_addr;`), or run depth mode with
  the matching `trusted_proxy.depth`.
- **A non-address entry means no client IP.** When the walk reaches an entry
  that is not an IP address (`unknown`, an empty field, a trailing comma, a
  range written with a prefix), the request has no client IP: every per-IP
  rate limit (account creation, anonymous secret creation, feedback, the
  legacy V1 API limits, and the per-IP tiers of the passphrase, login,
  password-reset, email-login and incoming limiters) charges it to one shared
  `no-client-ip` bucket, the admin network CIDR gate denies it, and sessions
  and audit records carry no address; the application does not fall back to
  the proxy's own address. A cap hit on the shared bucket is logged with that
  bucket's name. The entry can be written by a proxy or by the client itself:
  where clients have private addresses (a LAN, a VPN), an edge that appends
  the client address does not help, because that address is skipped as a
  trusted hop and the client's `unknown` to its left is reached. Have the edge
  overwrite `X-Forwarded-For` with the real peer address (appending is enough
  only when clients have public addresses), or use depth mode.
- **Vendor headers are not a source.** `CF-Connecting-IP`, `True-Client-IP`
  and similar headers are never read for the client IP, and with IP privacy on
  they are rewritten to the masked client IP before application code runs.

`depth` mode counts hops from the right instead of matching addresses and is
unchanged by the above, except that an invalid selected entry likewise leaves
the request with no client IP rather than resolving to the peer.

## Set public metadata at the proxy

Prefer preserving the public `Host` when the proxy permits it. If the proxy
must send the origin's hostname instead, use the supported
[`X-Forwarded-Host` contract](../operations/proxy-authority-header.md).

The proxy should overwrite or remove client-supplied forwarded host, port,
and scheme headers rather than pass them through. Generate accepted values
from the request and connection information the proxy has validated. Account
for competing carriers, including `Forwarded`, `X-Forwarded-Host`,
`X-Forwarded-Port`, `X-Forwarded-Proto`, and `X-Forwarded-SSL`; do not leave an
unused carrier available to influence another consumer.

**Trusting the peer does not prove who supplied the header value.** If an
authorized proxy passes through an attacker-supplied value unchanged, the
application cannot distinguish it from proxy-generated metadata without an
independent authenticated signal. A domain allowlist limits accepted names,
but it does not prove provenance or replace tenant authorization.

## Understand the rewrite's limits

`site.network.public_host_rewrite` is a compatibility setting, not a general
host-rejection policy. `PublicHostRewrite` rewrites only when the detected
host agrees with a supported domain classification and competing forwarded
host carriers have been removed. If those checks fail, it calls the next
application without rewriting; it does not itself reject the request.

Consequently, enabling rewriting is not evidence that unknown domains or
domain-lookup failures are rejected on sensitive routes. Verify those routes
separately, including authentication links, redirects, and tenant selection.

Rewriting also happens after the admin host gate, sessions, and identity
middleware. Earlier middleware initially sees the received host, while
mounted applications see the rewritten host. The environment is shared, so
earlier middleware can see the rewritten values on the response path. Test
host-dependent behavior on both sides of that boundary.

## Verify before serving traffic

Run these checks in an isolated deployment with the same proxy chain and
configuration as production. Use test accounts and domains; do not exercise
password-reset or SSO flows against real users.

| Check | What to verify |
| --- | --- |
| Origin access | Unauthorized public clients and unrelated private-network workloads cannot reach the origin. |
| Proxy trust | Trusted and untrusted peers receive the intended verdict; private peers are not accidentally trusted through a fallback or an overly broad range. |
| Header overwrite | Client-supplied forwarded host, port, and scheme values do not survive as authoritative metadata, including when a competing header is supplied. |
| Parsing | Duplicate or comma-separated hosts, malformed ports, and conflicting carriers cannot select an unintended tenant or URL destination. |
| Domain failures | Unknown domains and simulated domain-lookup failures cannot produce attacker-controlled authentication links, redirects, or access to another tenant. |
| Public URL consistency | Host, port, and scheme agree across generated links, redirects, origin checks, and SSO callbacks, including default and non-default ports. |
| Session boundary | Cookie scope and secure-cookie behavior remain correct before and after rewriting; switching domains does not cross authentication boundaries. |
| Admin isolation | Forwarded metadata and rewriting cannot bypass the configured admin host or network restrictions. |

Repeat relevant checks with rewriting enabled and disabled. Record the
configuration, request inputs, and observed outcomes. Application tests alone
cannot establish that a deployed proxy overwrites headers or that network
controls prevent direct origin access.

## Application hardening goals

External misconfiguration is not a reason to abandon application defenses.
Useful hardening goals include requiring explicit trust, rejecting malformed
or conflicting metadata, failing closed on domain-resolution errors on
sensitive routes, using one validated public authority downstream, and
refusing startup when required trust configuration is absent.

These are design goals, not a statement that every safeguard is implemented.
In particular, the private-peer fallback and the rewrite's pass-through
behavior described above remain important deployment considerations. The goal
is layered protection under an explicit deployment contract, not a promise
that normalization makes every proxy configuration safe.
