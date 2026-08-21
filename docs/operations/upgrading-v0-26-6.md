# Upgrading to v0.26.6

v0.26.6 is a follow-up to v0.26.5. It fixes three ways a **Host-rewriting proxy**
(Approximated ingress, and any origin-target rewriter) broke custom-domain
authentication: tenant SSO never resolved, SSO `redirect_uri`s named a host the
IdP had never seen, and transactional email links pointed at the canonical host
instead of the domain the recipient signed in from. It also closes a billing
federation gap and rebuilds the CI path that was supposed to be delivering
frontend sourcemaps to Sentry and never had.

There is **no schema migration and no bulk data transform**, so rollback is a tag
swap. Two things are worth reading before you upgrade rather than after:

- All three auth fixes are **inert unless your proxy is trusted**. They read the
  host the middleware tier resolved, and that tier honours forwarded host headers
  only from trusted infrastructure. If `TRUSTED_PROXY_ENABLED` is not `true`,
  nothing in this release changes for you.
- The **example Caddyfile changed for security reasons**, and one of its changes
  will break custom domains if you copy it verbatim while running behind
  Approximated. Read step 2 before you paste.

Coming from a version older than v0.26.5? Work through
[Upgrading to v0.26.5](upgrading-v0-26-5.md) first — this guide only covers the
v0.26.5 → v0.26.6 step.

## Before You Start

1. Back up your datastore. There is no migration, but there is no substitute
   either.
2. Record the tag you are on. Rollback is pinning it again.
3. Gather these facts — every step below needs at least one of them:
   - Whether anything in front of your origin **rewrites the `Host` header**
     (Approximated does; a plain reverse proxy that passes `Host` through does
     not).
   - The exact value of `TRUSTED_PROXY_ENABLED`, and if it is on,
     `TRUSTED_PROXY_MODE` / `TRUSTED_PROXY_CIDRS` / `TRUSTED_PROXY_DEPTH`.
   - Whether any tenant in your install uses **custom-domain SSO**, and which
     callback URLs are registered at their IdP.
   - Whether your Caddyfile (or equivalent) came from `etc/examples/Caddyfile-example`.
   - Whether **cross-region billing federation** is enabled.

## What Changes

| Area | Change | Action required? |
|---|---|---|
| Tenant SSO on custom domains | Credential lookup keys on the request's resolved public host, not the raw `Host:` the proxy rewrote | **Yes** behind a Host-rewriting proxy — the IdP must have the custom-domain callback URL registered |
| SSO `redirect_uri` / `callback_url` | Built from the public host for every strategy family (OIDC reads `client_options.redirect_uri`; OAuth2 builds `callback_url` itself) | **Yes**, same as above — this is the value the IdP compares |
| Transactional email links | Magic-link, password-reset, account-verification, verify-login-change and unlock emails point at the domain the recipient used, and the branding line matches | No, unless something downstream assumed a single link host |
| Proxy trust | Unchanged, but now **load-bearing for auth**: an untrusted proxy leaves all of the above resolving to the canonical host | **Yes** if you want the fixes to take effect |
| Example Caddyfile | Now strips client-supplied `X-Forwarded-Host`, `Forwarded`, and `Apx-Incoming-Host` | **Yes** if you derived your config from it — see the Caution in step 2 |
| New diagnostic route | `GET /api/colonel/system/proxy-headers` reports what Caddy received and what Rack resolved. Declares `network=admin`: 404 unless **both** admin allowlists are explicitly set and admit the request | Optional — only if you want the diagnostic |
| Billing federation | `customer.subscription.created` is now handled; a purchase in one region propagates to the buyer's orgs in other regions immediately instead of at the next subscription event | **Yes** on federated installs — enable the event at Stripe |
| Federation no-match logging | Both federation paths now emit a greppable `federation.no_match` warning carrying region, email hash, Stripe customer and subscription | No — worth an alert rule |
| `SENTRY_DIST` | Removed from `.env.reference`. Nothing ever read it; the dist tag is a build-time literal | No — delete it from your `.env` when convenient |
| `SENTRY_FRONTEND_PROJECT` | New **optional CI secret** (default `frontend`) naming the project sourcemaps upload to | Only if you build your own images and ship telemetry |
| Sourcemap delivery | The build now extracts the frontend from the pushed image, asserts before upload, and queries Sentry after it | Only if you build your own images |

## The Upgrade Checklist

Ordered by dependency. Proxy trust decides whether the auth fixes do anything at
all, so it comes first; the header hygiene in step 2 decides whether they resolve
the *right* host.

### 1. Confirm proxy trust, or the rest of this release is a no-op

`Rack::DetectHost` accepts a forwarded host **only** when the request arrived via
trusted infrastructure (`otto.via_trusted_proxy`) or from a private peer.
Everything in this release that fixes a host — tenant SSO resolution, the SSO
`redirect_uri`, and every minted email link — reads that resolution.

```bash
TRUSTED_PROXY_ENABLED=true
TRUSTED_PROXY_MODE=filter            # or depth
TRUSTED_PROXY_CIDRS=10.0.0.0/8       # filter mode: your proxy/CDN ranges
```

> **Caution.** `TRUSTED_PROXY_MODE`, `TRUSTED_PROXY_CIDRS` and
> `TRUSTED_PROXY_DEPTH` are inert unless `TRUSTED_PROXY_ENABLED=true`, and
> `filter` mode with no CIDRs trusts nothing. Either state leaves forwarded hosts
> discarded, which means custom-domain SSO and email links keep resolving to the
> canonical host exactly as they did in v0.26.5.

If you are behind Approximated, watch for this line at `WARN` after upgrading —
it is the precise signature of the failure this release fixes, still happening:

```
[DetectHost] Discarding forwarded host headers (Apx-Incoming-Host) from untrusted
source; Apx-Incoming-Host present — matches the 2026-08-05 Approximated-ingress
incident signature
```

### 2. Only if your proxy config came from the example: apply the header hygiene

`etc/examples/Caddyfile-example` previously passed the client's
`X-Forwarded-Host` and `Apx-Incoming-Host` straight through. `Rack::DetectHost`
takes the first syntactically valid hostname it finds in precedence order
(`X-Forwarded-Host` > `Apx-Incoming-Host` > `X-Original-Host` > `Forwarded` >
`Host`) and does **not** check that the domain belongs to this install. Passing
those headers through therefore lets any visitor who can reach the site block
choose the detected host.

```caddyfile
header_up Host {http.request.host}
header_up -X-Forwarded-Host
header_up -Forwarded
header_up -Apx-Incoming-Host          # see the Caution — NOT if Approximated fronts you
header_up X-Original-Host {http.request.host}
```

> **Caution — do not blanket-strip `Apx-Incoming-Host` if Approximated fronts
> this deployment.** That header is what carries the visitor's hostname while
> `Host:` holds the origin target; strip it unconditionally and every custom
> domain falls back to the canonical host. Gate it on source instead, using the
> ingress ranges from your Approximated dashboard. `header_up` does not accept
> matchers, so the strip goes in the enclosing `handle` block:
>
> ```caddyfile
> @not_apx not remote_ip 198.51.100.0/24
> request_header @not_apx -Apx-Incoming-Host
> ```

Two failure modes, worth knowing apart:

- An **unknown** injected host: `DomainStrategy` rejects it, falls back to the
  canonical host, and that tenant's SSO stops resolving.
- **Another tenant's registered** host: it is known, so it is honoured end to end
  — SSO resolution, sign-in gating and every minted link keyed to the wrong
  tenant.

Do not "fix" this by pinning `X-Forwarded-Host` to `{http.request.host}` either.
That outranks and masks `Apx-Incoming-Host`, which is the first failure mode by a
different route.

### 3. Only if you use custom-domain SSO: register the custom-domain callback at the IdP

Before this release, behind a Host-rewriting proxy, the `redirect_uri` handed to
the IdP was built from the rewritten authority — the origin target. It now names
the domain the visitor is actually on:

```
https://<custom-domain>/auth/sso/<provider>/callback
```

For every tenant with SSO on a custom domain, confirm that exact URL is in the
IdP application's allowed redirect URIs. Both phases (authorize and callback) run
the same resolution, so the two agree — but an IdP that only knows the old origin
target will reject the authorize request outright.

Deployments **not** behind a Host-rewriting proxy see no change here: the
authority already was the custom domain.

### 4. Only if billing federation is enabled: turn on the Stripe event

Federation previously ran on `customer.subscription.updated`, `.deleted`,
`.paused` and `.resumed`. There was no handler for `customer.subscription.created`
at all, so a purchase in region B by someone who already had an organization in
region A did not propagate until some later event on that subscription fired.

Add `customer.subscription.created` to the events your Stripe webhook endpoint
sends. Without it the handler never runs and nothing changes.

The handler is a no-op when federation is off, and on the purchasing region's own
organization it deliberately writes nothing — `checkout.session.completed` owns
that write path and compares the stored subscription id against the incoming one
to catch a replacement that would orphan a live subscription.

### 5. Optional: enable the proxy header diagnostic

`GET /api/colonel/system/proxy-headers` returns a fixed allowlist of
proxy-related fields — what Caddy observed before proxying, and what Rack
resolved after its proxy/IP middleware ran. It is the fastest way to answer "is
my forwarded host actually being trusted?" after steps 1 and 2.

The route declares `auth=sessionauth role=colonel` **and** `network=admin`. The
network requirement is stricter than the ordinary Colonel posture: both
allowlists must be explicitly configured and must admit the request. The
canonical-host fallback that ordinary Colonel routes accept does **not** satisfy
it.

```bash
ADMIN_ALLOWED_HOSTS=admin.example.com
ADMIN_ALLOWED_CIDRS=100.64.0.0/10
```

Add a dedicated Caddy handler ahead of the normal dynamic reverse-proxy handler,
so a caller cannot forge Caddy's own snapshots:

```caddyfile
@proxy_header_debug path /api/colonel/system/proxy-headers
handle @proxy_header_debug {
    header_up -X-Ots-Proxy-Debug-Peer
    header_up -X-Ots-Proxy-Debug-Host
    header_up -X-Ots-Proxy-Debug-Received-X-Forwarded-For
    header_up -X-Ots-Proxy-Debug-Received-Forwarded
    header_up -X-Ots-Proxy-Debug-Received-Apx-Incoming-Host

    header_up X-Ots-Proxy-Debug-Peer {remote_host}
    header_up X-Ots-Proxy-Debug-Host {http.request.host}
    header_up X-Ots-Proxy-Debug-Received-X-Forwarded-For {http.request.header.X-Forwarded-For}
    header_up X-Ots-Proxy-Debug-Received-Forwarded {http.request.header.Forwarded}
    header_up X-Ots-Proxy-Debug-Received-Apx-Incoming-Host {http.request.header.Apx-Incoming-Host}

    reverse_proxy 127.0.0.1:7143
}
```

Full detail in [Proxy header diagnostic](proxy-header-diagnostic.md).

### 6. Only if you build your own images: reconcile the Sentry project

Frontend stack traces have never symbolicated on any build produced by this
repo's workflow. The upload ran `sentry-cli sourcemaps upload ./public/web/dist`
on the runner, but the frontend is compiled *inside* the image and that directory
never existed at that point — and `sentry-cli` treats an empty directory as a
successful upload of zero artifacts, so every build reported green.

If you build your own images and ship telemetry:

```
SENTRY_FRONTEND_PROJECT=<project>     # optional, default "frontend"
```

It must be one of `SENTRY_PROJECTS`, or the release and its artifact bundles land
in different projects and symbolication silently fails again. The new preflight
reports that mismatch explicitly rather than passing quietly.

Delete `SENTRY_DIST` from your `.env`. Nothing in `lib/`, `apps/` or `src/` ever
read it; it read like a knob that could change the dist tag while offering no way
to set it.

## Verify

Work down this list — each check assumes the ones above it passed.

1. **Proxy trust is real.** Boot the new tag and grep the log for
   `[DetectHost] Discarding forwarded host headers`. Any hit naming
   `Apx-Incoming-Host` means step 1 is not done and steps 3–5 cannot work.
2. **Host resolution is correct.** With the diagnostic enabled, from an allowed
   admin host and network:

   ```bash
   curl -s https://admin.example.com/api/colonel/system/proxy-headers \
     -H 'Cookie: sess=<session-id>' | jq
   ```

   Confirm `rack.via_trusted_proxy` is true and `rack.detected_host` is the
   hostname a visitor types, not the origin target.
3. **A custom-domain email link names the custom domain.** Request a password
   reset from a tenant custom domain and read the delivered link. It must point
   at that domain, and the branding line in the body must name the same host.
4. **Tenant SSO completes.** Start SSO from a custom domain. Before this release
   the symptom was a `302` to `/signin?auth_error=sso_not_configured`; if you now
   get an IdP-side "unregistered redirect URI" error instead, step 3 of the
   checklist is outstanding, not this release.
5. **A test subscription federates.** With federation on, create a subscription
   in one region for an email that owns an org in another, and confirm the remote
   org picks up `subscription_federated_at` without waiting for a later event.
   Watch for `federation.no_match` warnings while you are there.

## Config Mapping Reference

### Renamed

Nothing renamed in this release.

### New

| Variable | Scope | Default | Notes |
|---|---|---|---|
| `SENTRY_FRONTEND_PROJECT` | **CI secret**, not runtime | `frontend` | Must be one of `SENTRY_PROJECTS` |

No new runtime environment variables.

### Removed

| Variable | Notes |
|---|---|
| `SENTRY_DIST` | Removed from `.env.reference`. Never read by application code; the dist tag is a build-time literal applied by the CI upload steps. Leaving it set is harmless |

### Changed behaviour (no variable changed name or default)

| Variable | What changed |
|---|---|
| `TRUSTED_PROXY_ENABLED` and friends | No parsing or default change — but the setting now also determines whether custom-domain SSO and transactional email links resolve the visitor's host |
| `ADMIN_ALLOWED_HOSTS` + `ADMIN_ALLOWED_CIDRS` | Unchanged for existing routes. A route declaring `network=admin` requires **both** to be explicitly set and active; the canonical-host fallback does not count |

## Troubleshooting

### `/api/colonel/system/proxy-headers` returns 404

Ambiguous by design — a rejected gate and a mistyped path look identical to the
client. Check the application log for
`Route network requirement not satisfied` from `NetworkRequirements` to confirm a
gate refused it, then work through, in order: is `ADMIN_ALLOWED_HOSTS` set
explicitly (not falling back to canonical)? Is `ADMIN_ALLOWED_CIDRS` set with at
least one parseable entry? Does your source address match one of them? Are you
signed in as a colonel?

### Custom-domain SSO still 302s to `/signin?auth_error=sso_not_configured`

The host is still not being resolved. Step 1, then step 2. Confirm with the
diagnostic that `rack.detected_host` is the custom domain.

### Custom-domain SSO now fails at the IdP with an unregistered redirect URI

Expected if step 3 is outstanding. The `redirect_uri` correctly names the custom
domain now; the IdP application still lists only the old origin target.

### Every custom domain fell back to the canonical host right after a proxy config change

You stripped `Apx-Incoming-Host` unconditionally while running behind
Approximated. Source-gate the strip — see the Caution in step 2.

### One tenant's users are landing in another tenant's context

Stop and check `X-Forwarded-Host` and `Forwarded` handling at the edge before
anything else. A pass-through of either lets a client name a *known* domain,
which is honoured end to end.

### Email links still point at the canonical host

Either proxy trust is not established (step 1), or your deployment does not
rewrite `Host` at all — in which case nothing changed for you and the links were
already correct.

### Frontend stack traces in Sentry are still unsymbolicated

Two halves must both be true, and this release ships only one of them. CI now
uploads with `--dist=frontend`; the frontend must put the matching
`dist: 'frontend'` on its own events in `src/plugins/core/enableDiagnostics.ts`.
Until that lands, the preflight reports the mismatch as an explicit dist-tag
warning on every run instead of staying silent.

## Rollback

There is no schema migration and no bulk data transform in this release, so
rollback is pinning the previous tag:

```bash
docker pull ghcr.io/onetimesecret/onetimesecret:v0.26.5
```

Nothing you configure while on v0.26.6 becomes invalid on v0.26.5:
`SENTRY_FRONTEND_PROJECT` is a CI-only secret, the admin allowlists behave the
same on both, and `TRUSTED_PROXY_*` is unchanged. The Caddyfile header hygiene in
step 2 is a strict improvement and should stay in place regardless of which tag
you run — it is not a v0.26.6 requirement, it is a spoofing fix.

The one thing that does not survive a rollback is the behaviour itself: on
v0.26.5 the SSO `redirect_uri` reverts to the origin target, so an IdP entry you
add in step 3 stops being the one used. Leave both URLs registered while you have
rollback in reach.
