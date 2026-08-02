.. A new scriv changelog fragment.

Added
-----

- Support staff can now answer "why can't this user log in or create an
  account" without SSH access. A new read-only diagnose operation
  (``Auth::Operations::Customers::Diagnose``) aggregates every relevant
  signal for one identifier — customer record state, Rodauth account status,
  lockout and consecutive login failures, pending verification / reset keys,
  MFA enrollment, active sessions, the authentication audit log tail, and the
  login rate limiter — and derives a severity-ordered findings list naming
  the blocking condition (locked out, rate limited, unverified with a stale
  verification email, email drift from a half-completed change, SSO-only
  account, orphaned auth account, suspended, or nothing found in this
  region). It is exposed twice over the single implementation: the
  ``bin/ots customers diagnose IDENTIFIER`` CLI command and a new Account
  Diagnostics panel on the colonel customer detail page
  (``GET /api/colonel/users/:user_id/diagnostics``). Every section degrades
  independently, so simple auth mode (no SQL authdb) still renders the
  Redis-side read-out. Identifiers can be an email, extid, or Rodauth
  account id; any of them resolving to no customer is still diagnosed
  against the auth database rather than 404ing, so orphaned accounts rows
  and "nothing exists here — check the other regions" both come back as
  findings instead of dead ends.

AI Assistance
-------------

- Feature implemented end-to-end (operation, CLI adapter, colonel endpoint,
  admin UI panel, specs) with Claude Code.
