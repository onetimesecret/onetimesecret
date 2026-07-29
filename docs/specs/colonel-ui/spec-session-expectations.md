# docs/specs/colonel-ui/spec-session-expectations.md

## created: 2026-07-27

Session management in a super admin has one architectural precondition that determines whether the rest is even possible: **revocation must be authoritative server-side**. Stateless JWTs with no denylist or short TTL + refresh rotation cannot satisfy "terminate this session now," and every compliance framework assumes you can. Decide that first; the feature list below is downstream of it.

**Inventory and visibility**

- All active sessions, filterable by user, tenant, IP, geo/ASN, device fingerprint/UA, auth method (password, SSO/IdP, API token), created-at, last-seen, expires-at.
- Per-session detail: opaque session ID (never the raw token or cookie value), MFA satisfied y/n and factor type, IdP subject, elevation/sudo state, impersonation flag.
- Concurrent session count per identity, and refresh-token family lineage if you use rotation.

**Termination**

- Revoke one session; revoke all for a user; revoke all for a tenant; global break-glass revoke.
- Cascade: killing a session must also invalidate refresh tokens, remember-me cookies, OAuth/PAT grants issued under it, and open WebSocket/SSE connections. Partial revocation is the most common real-world bug.
- Automatic revocation on password change, MFA enrollment change, role/permission change, and deactivation — event-driven, not an admin chore.
- A CLI path to revoke when the web UI is unreachable. Self-hosted operators will need this at exactly the worst moment.

**Policy**

- Idle timeout, absolute lifetime, remember-me max duration, step-up re-auth window (sudo mode) for destructive operations.
- Max concurrent sessions and the overflow behavior (deny new vs. evict oldest — pick one and make it explicit).
- Cookie hardening surfaced as config, not assumption: `__Host-` prefix, `Secure`, `HttpOnly`, `SameSite`, domain scoping. Session ID rotation on privilege elevation (fixation defense).
- Per-role and per-tenant overrides. Admin sessions should be strictly shorter than user sessions and should not share a cookie with the tenant-facing app.

**Impersonation**

Treat as a first-class, separate session type, not a login shortcut. Reason field required, time-boxed, non-nestable, revocable, optional read-only mode. Visible banner. All actions attributed to the real admin _and_ the target in the audit log. Cannot target other super admins. Notification to the impersonated user or their tenant admin, configurable — some regimes (health, finance) require it.

**Audit**

Append-only, tamper-evident, exportable to syslog/SIEM/webhook: session create, renew, expire, revoke (with actor and reason), impersonation start/stop, policy change, failed auth and lockout. Hash session identifiers; never log bearer material. Retention configurable because the self-hosted operator, not you, owns the retention obligation.

**Detection**

Surface anomaly signals in the admin rather than burying them in logs: impossible travel, new device/geo, refresh-token replay (which should auto-revoke the whole token family), simultaneous sessions from disparate ASNs. Lockout state visible and manually resettable. One-click quarantine = disable account + revoke everything.

**Compliance mapping worth naming explicitly in your docs**

NIST SP 800-63B: AAL2 = 30 min idle / 12 h absolute reauth; AAL3 = 15 min idle. PCI DSS 4.0 §8.6.x: 15 min idle. HIPAA §164.312(a)(2)(iii): automatic logoff. SOC 2 CC6.1/CC6.6 and ISO 27001 A.5.15–A.5.18 want the revocation capability plus the audit evidence. GDPR: session records contain IP and UA, therefore personal data — retention limits, inclusion in subject access export, deletion on erasure request.

**Self-hosted-specific, and usually missed**

Trusted proxy configuration. If you don't parse `X-Forwarded-For` against a configured trusted-hop list, every session row and every audit entry reads `127.0.0.1` and the compliance value of the whole feature is zero. Alongside that: document what secret/key rotation does to existing sessions (it should invalidate them, and operators should know before they rotate), version the session serialization format so upgrades don't silently drop or misparse sessions, and require no external network call for revocation so air-gapped deployments work.

**Anti-requirements**

Don't render raw tokens in the admin UI. Don't implement logout as a client-side cookie delete. Don't ship a "delete user" that leaves sessions live.
