# Blocking Cloudflare-fronted mirrors at the Bunny edge

Why unsanctioned mirrors of the regional sites can be refused at BunnyCDN with
one header rule, and why the rule belongs there rather than in Caddy or the
application. Assessment written 2026-08-27 from a Caddy access log on a
regional site; the log itself is not reproduced here. Whether the edge rule has
been applied is an operator question, not something the repository records.

## Why the predicate works now

The regional sites and the company websites sit behind BunnyCDN, and Bunny is
the only sanctioned edge. Any Cloudflare reverse-proxy artifacts that reach the
origin on a canonical host therefore mean a foreign Cloudflare zone or Worker
is fronting us. When the sites were behind Cloudflare themselves this was
undecidable: first-layer and second-layer Cloudflare proxying produced the same
headers. With Bunny in front it is a clean predicate.

## What the capture showed

The chain was longer than client to Cloudflare to Bunny. `Cf-Connecting-Ip`
named the address that hit the attacker's Cloudflare zone, but the address that
connected to Bunny, as seen in `X-Forwarded-For` and `X-Real-Ip`, was not a
Cloudflare egress range. The actor runs client, then their own Cloudflare zone,
then a relay box of their own, then Bunny, and the relay forwards Cloudflare's
headers untouched. The mirror kit also rewrites `Host`, `Origin` and `Referer`
to the regional hostname, which is why origin checks pass. Bunny's `Cdn-Ja4`
header fingerprints the relay's TLS client, a second axis if the actor starts
stripping headers.

## Which header to key on

Prefer `CDN-Loop: cloudflare` (RFC 8586) over `Cf-Ray` or `Cf-Connecting-Ip`.
A Cloudflare Worker can construct a clean outbound `fetch()` with the `Cf-*`
request headers stripped, but Cloudflare appends `CDN-Loop` on egress itself
for loop protection and customers cannot remove it. Bunny uses `Cdn-Loopcount`
for its own accounting and forwards the inbound `CDN-Loop` through, which is
what the capture showed. Caveat: this actor's relay box is not Cloudflare, so it
could strip `CDN-Loop`. The rule blocks the lazy mirrors, which is most of them
including this one, not a determined header-scrubbing one.

## Where to enforce

A Bunny Edge Rule on the regional pull zones: condition "request header
`CDN-Loop` contains `cloudflare`", action Block (403). That is the right layer
for three reasons. The request never reaches origin. The rule is inherently
scoped to canonical hosts, because custom domains CNAME to the cluster and do
not ride these pull zones, so a customer legitimately orange-clouding their own
custom domain through Cloudflare is unaffected. And it needs no application
deploy. A Caddy or middleware equivalent would have to carry host-scoping logic
to avoid that custom-domain false positive, which is the class of seam bug the
#4224 host-detection matrix exists to catch.
