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
- **Review every hop.** For a CDN, load balancer, and ingress chain, identify
  where client-supplied metadata is discarded and which hop supplies the
  values the application consumes. Recheck trust ranges when topology changes.

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
