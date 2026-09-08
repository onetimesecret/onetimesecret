# Rodauth Admin — moved to its own codebase

The specs that lived here (`00-scope.md`, `10-aggregate-visibility.md`) scoped a
web admin UI for the Rodauth (`full`-mode) authentication system as a graft
inside the colonel console. That plan was reversed on 2026-09-01: Rodauth Admin
is a **standalone application** over the authdb, developed and deployed
separately.

- Repository: `onetimesecret/rodauth-admin`
- Charter (the pivot, what the codebase owns, phasing): `docs/CHARTER.md` there
- The two documents formerly here, kept verbatim: `docs/specs/inherited/` there
- Hosting decision (own process behind an SSH tunnel, never a mount):
  `docs/decisions/0001-standalone-process-not-a-mount.md` there

## What remains in this repo

Exactly the three integration seams the charter allows (§4). No shared session,
no cross-service API call; the admin is only ever *linked to*.

| Seam | Where |
|---|---|
| Outbound deep links to the matching Rodauth account, keyed by `accounts.external_id == Customer.extid`: the customer detail page, the customers list drawer, and every row and drawer of the sessions console | `lib/onetime/rodauth_admin.rb`; `rodauth_admin_account_url` on `GET /api/colonel/users` rows, `GET /api/colonel/users/:extid` details, `GET /api/colonel/sessions` rows and `GET /api/colonel/sessions/:handle` record; also on `Auth::Operations::Customers::Show` for the CLI |
| The sessions console and per-customer sessions panel say they are **not** the session authority in `full` mode and link out | `ColonelAPI::Logic::Colonel::SessionAuthority` (`details.session_authority` on both listings), `SessionAuthorityNotice.vue` |
| The dev-only stats stub `apps/web/auth/routes/admin.rb` | Deleted |

Both links are built from `site.admin.rodauth_admin_url` (env
`RODAUTH_ADMIN_URL`). It is optional and carries no credential; unset renders
plain text. The reverse link (admin → colonel customer page) is
`COLONEL_CONSOLE_URL` on the admin side.
