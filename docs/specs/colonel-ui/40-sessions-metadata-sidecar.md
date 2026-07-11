---
labels: admin-v2, addendum, backend, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui, 40-sessions-console
epic: n/a
status: implemented
branch: feature/colonel-sessions
---

## Status: implemented

Shipped on `feature/colonel-sessions` (branches off `422ef114d`) as six granular
commits:

| Commit      | Layer                                                                   |
| ----------- | ----------------------------------------------------------------------- |
| `6cb5ff840` | `SessionMetadata` sidecar model + `Customer#active_sessions` index      |
| `02cac12ce` | populate hook (`Session#write_session` → `TrackMetadata`) + sidecar ops |
| `69f21d0cb` | colonel list + revoke endpoints                                         |
| `a0a9a6e94` | customer sessions panel + Pinia store + zod schema                      |
| `1fcf16caf` | tryouts + vitest specs + this doc                                       |
| `e5321e5de` | Finding #1 fix — prune dead-blob rows from the list                     |

The build deviated from the original proposal below in several **deliberate**
ways, each driven by how this codebase actually invalidates a session. The
proposal text is preserved after this section for the design rationale, but where
it disagrees with the table below, **the table is authoritative.**

### What shipped vs. what the proposal said

| Proposal                                                                       | Shipped                                                                                | Why                                                                                                                                                                                                                                                                                                                                                              |
| ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key by `HMAC(sid)` to join the Rodauth index                                   | Key by the **plain sid**, prefix `session_metadata:<sid>`                              | A session dies here by deleting the encrypted `session:<sid>` blob, **not** by removing a Rodauth `active_session_keys` row (that table only gates Rodauth-mounted routes in mode=full). Joining on an HMAC buys nothing; the plain sid adds no exposure (it's already the blob's key name) and lives under a distinct prefix so it can't collide with the blob. |
| Populate in Rodauth `after_login`                                              | Populate in `Onetime::Session#write_session` via `Operations::Sessions::TrackMetadata` | `write_session` is the one place the plain sid and the authenticated `session_data` co-exist, and it re-fires ~per request so `last_activity_at` stays fresh. Best-effort (own begin/rescue) — a sidecar failure never breaks auth.                                                                                                                              |
| `ip_masked`, `asn`, `geo_country`, `device_label`, `flagged_at`, `flag_reason` | Raw `ip_address`, `user_agent` copied **as-is**; geo/asn/device/flag fields dropped    | Otto already masks IP/UA upstream, so no masking logic is built here. Geo/ASN enrichment and anomaly-flagging were out of scope for the first cut.                                                                                                                                                                                                               |
| `org_id` = org objid                                                           | `org_id` = **active org objid**, resolved per write                                    | The session caches the active org under the key _string_ `org_context:<customer.objid>` — the suffix namespaces the entry by _customer_ and is NOT an org id, but the key's _value_ (`{ organization_id: <org.objid>, … }`) carries the real org objid. `TrackMetadata#active_org_id` calls the canonical `OrganizationLoader` (read-through: resolves on cache miss, e.g. the login write), so every authenticated session's metadata carries the active org. Org is mutable mid-session (org switcher), so it is resolved on every write, not stamped once. |
| `auth_method` incl. `'password'`                                               | primary method **stamped once at auth time**: `'password'` \| `'email_auth'` \| `'webauthn'` \| `'omniauth'` \| nil | Stamped in `after_login` from Rodauth's `authenticated_by.first` (the primary login method) into `session['auth_method']`, then copied verbatim by `TrackMetadata`. NOT re-derived per write — the mechanism leaves no trace in `session_data` by write time (omniauth markers are deleted; password/magic-link/webauthn never wrote one). nil only for legacy sessions minted before the stamp existed. |
| `custid` field                                                                 | `user_id` = customer **external id** (extid, `ur…`)                                    | Matches colonel identity everywhere else; the colonel surface routes by extid, not objid.                                                                                                                                                                                                                                                                        |
| Routes `/customers/:custid/sessions`                                           | `/users/:user_id/sessions`                                                             | There is no `/customers` colonel surface; the convention is `/users/:user_id` (documented in `Base.rb`).                                                                                                                                                                                                                                                         |
| Revoke → `rodauth.remove_active_session_for`                                   | Revoke deletes the live `session:<sid>` **blob** (`Store.find_key` → `db.del`)         | Deleting the blob is the actual logout on the blob-validated request path. The Rodauth SQL row is left untouched (it self-expires and only gates Rodauth-mounted routes).                                                                                                                                                                                        |
| —                                                                              | Blob-liveness reconcile on list (Finding #1)                                           | The sidecar's 30d TTL outlives the blob's 24h default, so the list would show dead sessions as active. `ListForCustomer` prunes any sid whose `session:<sid>` blob is gone via an EXISTS-only probe — no decrypt, no scan.                                                                                                                                       |
| Standalone admin `/sessions` route + composable                                | Panel embedded in `AdminCustomerDetail.vue`; Pinia store                               | The sidecar is a per-customer view; it belongs on the customer-detail page, not a global route. The global `/sessions` console (scan+decrypt) stays as the authoritative site-wide incident view.                                                                                                                                                                |
| revoke-all → tracked-only OR scan-first                                         | revoke-all → **tracked-index kill (guaranteed) + best-effort scan sweep**               | Two-tier. (a) Every sid in `active_sessions` is deleted directly via `Store.find_key`+`del` — exact, UNCAPPED, cap-proof, the guaranteed kill. (b) A bounded scan then sweeps for genuinely untracked (pre-sidecar) blobs. Scan-FIRST would be unsafe: `MAX_SCAN`=10k in an anonymous-dominated 200k-account keyspace can miss the target's tracked blobs while tidy destroys their sidecars → live-but-invisible session, silent "0 killed". `scan_capped` is surfaced so a truncated sweep is visible, not silent. |
| revoke-all → `rodauth.remove_all_active_sessions_for`                           | revoke-all clears `account_active_session_keys` via **direct Sequel** (full mode only) | The ops layer has no bound Rodauth instance, so it can't call the helper — it does the same DELETE `CloseAccount` does, resolving `account_id` from `accounts.external_id`. Guarded on the auth DB being present (nil in simple mode → skipped).                                                                                                                   |
| single-revoke leaves the Rodauth SQL row (self-expires)                         | revoke-all **clears** the Rodauth SQL row immediately                                   | Offboarding wants Rodauth-mounted routes locked at once, not on self-expiry. This is the one place the deliberate "leave the SQL row" choice of single-revoke is reversed — because the intent is total lockout, not one-session logout.                                                                                                                          |

### Files

**Backend**

- `lib/onetime/models/session_metadata.rb` — the sidecar model (9 fields, 9-field positive `safe_dump` allow-list).
- `lib/onetime/models/customer.rb` — `sorted_set :active_sessions` (member: sid, score: last-activity epoch).
- `lib/onetime/session.rb` — best-effort `TrackMetadata` call in `write_session`.
- `lib/onetime/operations/sessions/track_metadata.rb` — populate op (upsert + ZADD).
- `lib/onetime/operations/sessions/list_for_customer.rb` — read op (revrange → `safe_dump`, blob-liveness reconcile).
- `lib/onetime/operations/sessions/revoke_for_customer.rb` — single-revoke op (blob del + tidy + one audit event).
- `lib/onetime/operations/sessions/revoke_all_for_customer.rb` — revoke-all op (scan-kill all matching blobs + tidy sidecars/index + clear Rodauth SQL rows in full mode + one audit event).
- `lib/onetime/operations/sessions/store.rb` — shared key primitives (`find_key` EXISTS probe + `scan_keys`, reused by list / revoke / revoke-all).
- `apps/api/colonel/logic/colonel/{list_customer_sessions,revoke_customer_session,revoke_all_customer_sessions}.rb` — thin colonel adapters.
- `apps/api/colonel/routes.txt` — the three routes (list GET, revoke-all POST, single-revoke DELETE).

**Frontend**

- `src/schemas/api/internal/responses/colonel-customer-sessions.ts` — zod, the `safe_dump` shape verbatim.
- `src/apps/admin/stores/useAdminCustomerSessions.ts` — Pinia store (`fetchForCustomer`, `revoke`, `revokeAll`).
- `src/apps/admin/components/AdminCustomerSessionsSection.vue` — the panel (DataTable + guarded per-row revoke + guarded revoke-all, the latter typed-gated on the customer's extid).
- `src/apps/admin/views/AdminCustomerDetail.vue` — mounts `<AdminCustomerSessionsSection :user-id="publicId" />`.
- `locales/content/en/admin-customers.json` — session i18n keys (incl. the `revokeAll.*` group).

**Tests**

- `try/unit/models/session_metadata_try.rb`
- `try/unit/operations/sessions/{track_metadata,list_for_customer,revoke_for_customer,revoke_all_for_customer}_try.rb`
- `try/integration/api/colonel/{list_customer_sessions,revoke_customer_session,revoke_all_customer_sessions}_try.rb`
- `src/tests/apps/admin/useAdminCustomerSessions.spec.ts`, `AdminCustomerDetail.spec.ts`

### Known follow-ups (not blockers)

- **`revoke-all-for-account` — BUILT** (offboarding / takeover): `RevokeAllForCustomer` + `POST /users/:user_id/sessions/revoke-all`. Guaranteed kill of the tracked index (uncapped, cap-proof) + a best-effort scan sweep for untracked pre-sidecar blobs (`scan_capped` surfaced), plus clearing the Rodauth `account_active_session_keys` rows in full mode. Integration + unit tryouts included (incl. a cap-proof regression: a mislabeled tracked blob the scan would skip is still killed by index membership). The **full-mode Rodauth SQL DELETE is inspection-verified only** — test mode is simple, so `rodauth_rows_deleted` is always 0 there. See the revoke-all deviation rows above.
- **Backfill gap (by design)** — the sidecar only populates forward, on the next authenticated `write_session`. Pre-existing sessions have no sidecar until they churn; the global console covers them. No backfill script (it would reintroduce the scan+decrypt this feature avoids).
- **`auth_method` and `org_id` are now populated** — `auth_method` is stamped at `after_login` (primary method from Rodauth `authenticated_by`); `org_id` is resolved per write via `OrganizationLoader`. Both are safe to surface. Only **`mfa_used`** remains latent (always nil) — a second-factor stamp (from `after_two_factor_authentication`) is the follow-up. Legacy sessions minted before this change carry nil `auth_method`/`org_id` until they churn.
- **Rodauth SQL `active_session_keys` row not tidied on revoke** (mode=full) — harmless orphan that self-expires; optional tidy only if the Rodauth self-service list must stay consistent.
- **Current-session indicator — BUILT.** `ListCustomerSessions` returns `details.current_session_id` (the acting colonel's own request sid, via `safe_session_id.public_id`). When it matches a listed row (colonel viewing their own detail), the panel badges that row "This session" and disables its per-row revoke instead of offering a no-op button: revoking your **own** current session is a no-op because Rack's `write_session` re-persists the blob at the end of the same request. Revoke-all is unaffected. Nullable/absent when the current session isn't in the list or can't be identified.
- **Cross-owner single-revoke audit attribution — HARDENED.** Single-revoke is colonel-only, so it does **not** gate the blob delete on ownership (takeover mitigation must not be blocked by best-effort sidecar state). But when the sidecar's recorded `user_id` differs from the route customer, `RevokeForCustomer` records `session_user_id` in the audit detail so the action is not silently mis-attributed. The true owner's stale index member self-heals via `ListForCustomer`'s blob-liveness prune.

---

## Original proposal (design rationale — superseded on specifics by the table above)

### The key constraint Redis imposes

Your session _contents_ live at `session:<sid>` as the AES-256-GCM blob (per `lib/onetime/session.rb`), and your active-session _index_ is the Rodauth `account_active_session_keys` set keyed by the HMAC-hashed sid. Neither is a good backing store for an admin list on its own: the encrypted blob can't be filtered by customer without decrypting it, and the Rodauth index only holds `created_at`/`last_use`.

So the anti-pattern to avoid is the obvious one: `SCAN session:*` → decrypt each → filter by account. That's O(all sessions), it forces decryption of every user's payload into admin memory, and it's exactly the surface you were worried about. Don't build the panel on it. (The **global** console at `GET /sessions` _does_ use that pattern deliberately — it's the authoritative site-wide incident view, bounded by a scan cap and a string-type filter. The sidecar exists so the **per-customer panel** never has to.)

Instead, write a **metadata sidecar** at session-mint time — a small, non-secret, unencrypted record per session plus a per-customer index. Familia makes this native, and it means the admin path never touches the encrypted blob at all.

### Redis schema (Familia) — as shipped

The record is keyed by the **plain sid** (see the deviation table for why not HMAC), under a distinct `session_metadata:` prefix, with a TTL that mirrors the session lifetime so it self-cleans:

```ruby
# lib/onetime/models/session_metadata.rb
module Onetime
  class SessionMetadata < Familia::Horreum
    feature :safe_dump
    feature :expiration

    prefix :session_metadata
    identifier_field :session_id
    default_expiration 2_592_000 # 30d — mirror max session lifetime

    field :session_id # plain sid; also the identifier and the blob key name
    field :org_id # active ORGANIZATION objid, resolved per write via OrganizationLoader
    field :user_id # customer EXTERNAL id (extid, 'ur...')
    field :created_at # epoch seconds, set once
    field :last_activity_at # epoch seconds, refreshed every write
    field :ip_address # copied AS-IS (already masked upstream by Otto)
    field :user_agent # copied AS-IS (already masked upstream by Otto)
    field :auth_method # primary method stamped at auth time: 'password' | 'email_auth' | 'webauthn' | 'omniauth' | nil
    field :mfa_used # true | false | nil

    # POSITIVE allow-list — the security boundary. No token, no payload, no email.
    safe_dump_fields(
      :session_id,
      :user_id,
      :org_id,
      :created_at,
      :last_activity_at,
      :ip_address,
      :user_agent,
      :auth_method,
      :mfa_used,
    )
  end
end
```

And a per-customer index so the admin list is O(sessions-for-this-user), not a global scan — a `sorted_set` scored by last activity, alongside the existing `sorted_set :receipts` in `customer.rb`:

```ruby
# in Customer
sorted_set :active_sessions # member: sid, score: last_activity epoch
```

Population happens in `Onetime::Session#write_session` (not a Rodauth hook — see the table) via `Operations::Sessions::TrackMetadata`, best-effort with its own rescue, refreshing `last_activity_at` and the sorted-set score on each authenticated write. Geo/ASN/device enrichment was dropped from the first cut.

The `safe_dump_fields` allow-list is doing the real security work here: it's a positive allow-list, so even if someone later adds an `email` or `raw_ua` field to the model, it can't leak through the serializer without an explicit edit. That's the structural guarantee that the admin panel stays metadata-only.

### Colonel backend (apps/api/colonel) — as shipped

Read + revoke only, role-gated (`role=colonel`), audited on mutation. The routes use the `/users/:user_id` convention:

```
GET    /users/:user_id/sessions              ColonelAPI::Logic::Colonel::ListCustomerSessions
DELETE /users/:user_id/sessions/:session_id  ColonelAPI::Logic::Colonel::RevokeCustomerSession
```

The logic classes are thin adapters over the operations:

- **`ListForCustomer`** reads `Customer#active_sessions` (revrange, newest-first) → `SessionMetadata.load` per sid → `safe_dump`. No scan, no decrypt. It reconciles against the live blob: a sid whose sidecar is gone is ZREM'd; a sid whose sidecar is present but whose `session:<sid>` blob is gone (dead session the 30d sidecar hasn't caught up to) has its orphan sidecar destroyed and is hidden — via the same EXISTS-only `Store.find_key` probe the revoke path uses. Reads write **no** audit event.
- **`RevokeForCustomer`** deletes the live `session:<sid>` blob (`Store.find_key` → `db.del`) — the actual logout — then destroys the sidecar, ZREMs the index member, and writes exactly **one** `AdminAuditEvent` (verb `session.revoke`, actor = acting colonel's extid, target = the customer). It does **not** delegate to the global `Delete` op (that would double-audit with a different target) and does **not** touch the Rodauth SQL row (deliberate — see the table). Idempotent: revoking an already-gone session still tidies + audits, reporting `blob_deleted: false`.

### Frontend (src/apps/admin) — as shipped

Not a standalone route — a panel mounted inside the customer detail view, since the sidecar is inherently per-customer:

- **`useAdminCustomerSessions.ts`** (Pinia setup store): `fetchForCustomer(userId)` → `GET /api/colonel/users/:user_id/sessions`; `revoke(userId, sessionId)` → `DELETE …/:session_id`, then optimistically drops the row.
- **`AdminCustomerSessionsSection.vue`**: a `DataTable` of the `safe_dump` rows (last activity, IP, device, auth method) with a guarded revoke per row (`AdminConfirmDialog`, danger variant). Revoke logs the user out mid-flight, so it's confirm-gated client-side and audited server-side.
- Mounted in `AdminCustomerDetail.vue` as `<AdminCustomerSessionsSection :user-id="publicId" />`.

The `AdminCustomerSession` zod type is the `safe_dump` shape verbatim — `session_id`, `user_id`, `org_id`, timestamps, `ip_address`, `user_agent`, `auth_method`, `mfa_used`. No `token`, no payload field exists in the type, so the frontend _can't_ render one even by accident.

### Where the CLI / global-console decrypt path fits

`ots session inspect` (and the global `GET /sessions` console) still decrypt the blob and show email/role/IP/UA — keep those as the deliberate break-glass for real incidents: operator-audited, not wired into the per-customer panel. The panel gets metadata + revoke; the rare "I need to see what this session actually held" stays a separate, logged action.

Net change from the SQL version: a Familia `SessionMetadata` sidecar + a `Customer#active_sessions` sorted-set index written at `write_session` time, so the colonel per-customer view reads only non-secret metadata and never `SCAN`-and-decrypts the Redis session blobs.
