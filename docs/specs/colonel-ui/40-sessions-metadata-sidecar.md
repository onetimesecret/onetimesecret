---
labels: admin-v2, addendum, backend, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui, 40-sessions-console
epic: n/a
---

## The key constraint Redis imposes

Your session *contents* live at `session:<sid>` as the AES-256-GCM blob (per `lib/onetime/session.rb`), and your active-session *index* is the Rodauth `account_active_session_keys` set keyed by the HMAC-hashed sid. Neither is a good backing store for an admin list on its own: the encrypted blob can't be filtered by customer without decrypting it, and the Rodauth index only holds `created_at`/`last_use`.

So the anti-pattern to avoid is the obvious one: `SCAN session:*` → decrypt each → filter by account. That's O(all sessions), it forces decryption of every user's payload into admin memory, and it's exactly the surface you were worried about. Don't build the panel on it.

Instead, write a **metadata sidecar** at session-mint time — a small, non-secret, unencrypted record per session plus a per-customer index. Familia makes this native, and it means the admin path never touches the encrypted blob at all.

## Redis schema (Familia)

A metadata object keyed by the **hashed** sid (same value Rodauth stores, so they join cleanly), with a TTL matched to your session lifetime so it self-cleans:

```ruby
# lib/onetime/models/session_metadata.rb
module Onetime
  class SessionMetadata < Familia::Horreum
    feature :expiration
    feature :safe_dump_fields

    identifier_field :sid_hmac
    default_expiration 2_592_000   # 30d — mirror session_lifetime_deadline

    field :sid_hmac        # HMAC(sid) — NOT the raw sid, never the cookie value
    field :org_id   # uuidv7 org.objid
    field :user_id  # uuidv7 cust.objid
    field :created_at
    field :last_activity_at
    field :ip_masked        # /24 or /48 — truncate at write time
    field :asn
    field :geo_country
    field :device_label    # parsed "Chrome on macOS", not raw UA
    field :auth_method     # 'password' | 'oidc' | 'omniauth:google' ...
    field :mfa_used
    field :flagged_at
    field :flag_reason

    # Whitelist what the colonel API may serialize. Note what's absent:
    # no token, no decrypted payload, no email/secret material.
    safe_dump_fields :sid_hmac, :custid, :created_at, :last_activity_at,
                     :ip_masked, :asn, :geo_country, :device_label,
                     :mfa_used, :flagged_at, :flag_reason
  end
end
```

And a per-customer index so the admin list is O(sessions-for-this-user), not a global scan — a `sorted_set` scored by last activity, alongside the existing `sorted_set :receipts` in `customer.rb`:

```ruby
# in Customer
sorted_set :active_sessions   # member: sid_hmac, score: last_activity epoch
```

Populate both in your Rodauth `after_login` / session-renewal hook (the same place your route already computes `compute_hmac(session_id)`), and refresh `last_activity_at` / the sorted-set score on the activity path where `currently_active_session?` already fires. Geo/ASN enrichment runs async off the truncated IP — never on the request path.

The `safe_dump_fields` whitelist is doing the real security work here: it's a positive allow-list, so even if someone later adds an `email` or `raw_ua` field to the model, it can't leak through the serializer without an explicit edit. That's your structural guarantee that the admin panel stays metadata-only.

## Colonel backend (apps/api/colonel)

This slots next to your existing `banned_ip` model and colonel logic. Read + revoke only, role-gated, MFA-gated, audited:

```ruby
# apps/api/colonel/logic/list_customer_sessions.rb
module Onetime::Colonel::Logic
  class ListCustomerSessions
    def process
      raise_unless_colonel!(@cust)                  # RBAC
      customer = Onetime::Customer.load(@custid)
      customer.active_sessions.revrangebyscore('+inf', '-inf').map do |sid_hmac|
        SessionMetadata.load(sid_hmac)&.safe_dump   # metadata only — no blob read
      end.compact
    end
  end

  class RevokeSession
    def process
      raise_unless_colonel!(@cust)
      rodauth.remove_active_session_for(@custid, @sid_hmac)  # kills index entry
      Onetime::SessionMetadata.load(@sid_hmac)&.destroy!     # tidy sidecar
      # note: the encrypted session:<sid> blob expires on its own TTL;
      # revoking the index entry is what invalidates the session.
      audit_log!(:colonel_session_revoke, actor: @cust.custid,
                 target: @custid, meta: { sid_hmac: @sid_hmac })
      { success: true }
    end
  end
end
```

Route mirrors the colonel app's style; every list and revoke writes an append-only audit entry (who acted on whose sessions). A `revoke-all-for-account` variant maps to Rodauth's `remove_all_active_sessions_for` for the offboarding / account-takeover case.

## Frontend (src/apps/admin)

`src/apps/admin` is greenfield right now (just a `.DS_Store`), but you already have the exact pattern to copy from: `useActiveSessions.ts` and the `Session` type. Make an admin-scoped sibling rather than reusing the self-service one, since it hits colonel endpoints and carries an account column:

```ts
// src/apps/admin/composables/useAdminSessions.ts
import { adminSessionsResponseSchema, type AdminSession } from '@/schemas/api/colonel/sessions';

export function useAdminSessions() {
  const $api = inject('api') as AxiosInstance;
  const sessions = ref<AdminSession[]>([]);

  async function fetchForCustomer(custid: string) {
    const res = await $api.get(`/api/colonel/customers/${custid}/sessions`);
    sessions.value = adminSessionsResponseSchema.parse(res.data).sessions;
  }
  async function revoke(custid: string, sidHmac: string) {
    await $api.delete(`/api/colonel/customers/${custid}/sessions/${sidHmac}`, {
      data: { shrimp: csrfStore.shrimp },
    });
    sessions.value = sessions.value.filter((s) => s.sid_hmac !== sidHmac);
  }
  return { sessions, fetchForCustomer, revoke };
}
```

The `AdminSession` zod type is the `safe_dump` shape verbatim — `sid_hmac`, `custid`, timestamps, `ip_masked`, `asn`, `geo_country`, `device_label`, `mfa_used`, `flagged`, `flag_reason`. No `token`, no payload field exists in the type, so the frontend *can't* render one even by accident. Reuse the `SessionListItem.vue` layout from `workspace/account`, add a flagged-state badge so colonels triage by anomaly signal rather than reading rows, and gate the whole route behind the colonel role in the admin app's router.

## Where the CLI decrypt path fits

Your `ots session inspect` in `lib/onetime/cli/session_command.rb` still decrypts the blob and prints email/role/IP/UA — keep that, but as the deliberate break-glass for real incidents: CLI-only, operator-audited, not wired into the panel. The panel gets metadata + revoke; the rare "I need to see what this session actually held" stays a separate, logged action.

Net change from the SQL version: a Familia `SessionMetadata` sidecar + a `Customer#active_sessions` sorted-set index written at login, so the colonel API and the new `src/apps/admin` view read only non-secret metadata and never `SCAN`-and-decrypt the Redis session blobs.

Want me to scaffold this for real into a branch — the `SessionMetadata` model, the `after_login` hook, the colonel logic/route, and the `src/apps/admin` composable + view — with specs in your existing style? I can wire it up and run the relevant `rspec`/`vitest` before handing it back.
