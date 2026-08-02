---
labels: admin-v2, backend, security, ops
depends: none
epic: "#3653"
---

# Admin rebuild: opt-in network isolation middleware (site.admin.allowed_cidrs)

## Context

Part of the Colonel Admin Rebuild epic (Phase 4). One codebase, two postures by config. On cloud (onetimesecret.com) we want `/colonel` and `/api/colonel` reachable only from Tailscale/private ranges as defense-in-depth on top of the two auth layers. Self-hosted single-container installs cannot require a VPN, so isolation must be an opt-in config posture — not an architecture fork. This adapts the one research recommendation ("network-level isolation / bind to private network") to fit both deployment shapes.

## Scope

- Add a `site.admin.allowed_cidrs` Rack middleware, a sibling of the existing `IPBan` and `HealthAccessControl` middleware (same Rack middleware pattern).
- When enabled with a private-CIDR allowlist: requests originating outside the allowlist get a 404 on `/colonel` and `/api/colonel` (indistinguishable-from-absent, not 403).
- Absent from self-hosted defaults: OFF by default, zero new config required for single-container installs to keep working.
- Cloud config enables it with private CIDRs; document it for operators fronting self-hosted with Caddy or a reverse proxy.

## Grounding — files & pointers

- Sibling middleware (Rack pattern to mirror): `IPBan` and `HealthAccessControl` middleware.
- Middleware example with request context: `apps/web/core/middleware/request_setup.rb` (nonce middleware).
- Protected surfaces: `/colonel` + `/colonel/*` shell (`apps/web/core/routes.txt:88-90`) and the `/api/colonel` API (`apps/api/colonel/routes.txt`).
- Config key: `site.admin.allowed_cidrs`.

## Acceptance criteria

- [ ] `site.admin.allowed_cidrs` middleware exists, registered as a sibling of `IPBan`/`HealthAccessControl`.
- [ ] When configured, a request from outside the allowlist to `/colonel` or `/api/colonel` returns 404.
- [ ] When configured, a request from inside the allowlist passes through to the normal auth layers.
- [ ] Unset/empty allowlist = middleware is a no-op (both surfaces reachable; app-layer authz unchanged). This is the self-hosted default.
- [ ] Both auth layers still enforce beneath the middleware (defense-in-depth, not a replacement).
- [ ] Operator docs cover cloud enablement and the reverse-proxy alternative for self-hosted.

## Notes / risks

- Return 404, not 403, so the surface is indistinguishable from absent to an unauthorized network.
- Client IP must come from the trusted-proxy-resolved address, not a raw header — reuse the existing IP resolution the sibling middleware relies on, or the allowlist is spoofable.
- Isolation is a config posture, not a code fork: identical app-layer enforcement in both postures.
