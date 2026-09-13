# apps/web/auth/migrations/009_webauthn_surface_scope.rb
#
# frozen_string_literal: true

# Per-surface WebAuthn credential scoping (#4414, epic #4408).
#
# WHY: WebAuthn credentials are cryptographically bound to the origin (rp_id)
# they were registered against — a passkey registered at the canonical host
# cannot verify at `tenant.customer.com`. Until this migration, the
# account_webauthn_keys table carried no record of WHICH origin each row was
# registered on, so the tenant re-authentication UI (#4414) could not tell a
# platform-only credential from a tenant-scoped one when deciding what to
# OFFER. The floor holds by construction (a mismatched credential fails the
# ceremony), but a UI must not present a button whose ceremony will fail —
# {Onetime::ReauthPolicy} needs positive evidence about registration surface
# per row.
#
# COLUMN: surface_scope holds a JSON-encoded {Onetime::SessionSurface}
# descriptor string:
#
#   NULL           — legacy row registered before this ships (treated as
#                    :platform, i.e. offerable on :canonical only, by
#                    ReauthPolicy's unknown-scope default; historical rows
#                    are overwhelmingly canonical registrations)
#   '{"kind":"canonical"}'
#   '{"kind":"subdomain","host":"eu.example.com"}'
#   '{"kind":"custom","id":"<CustomDomain identifier>"}'
#
# STRING rather than a native JSONB column: SQLite's JSON support is a shim
# on TEXT storage, so a portable schema keeps it TEXT and lets the app parse.
# The value is opaque to Rodauth (which never reads this column) and to the
# webauthn gem (which reads only public_key / sign_count / last_use), so no
# storage layer has an opinion about its shape.
#
# NULLABLE by design. A backfill would need each row's registration origin,
# which we have no record of — the whole reason for this column. The read
# path in Auth::Operations::ReadWebauthnCredentials treats NULL as :platform,
# which matches the historical single-origin deployment and is the same
# refusal ReauthPolicy already applies to a :platform credential on a tenant
# surface. Rows registered after this ships carry a real descriptor and
# unlock per-surface offer rules.
#
# INDEX: intentionally NONE. The column is read only alongside a row already
# selected by (account_id, webauthn_id), so it rides the existing composite
# primary key. Filtering on surface_scope alone (e.g. "all credentials for
# tenant X") is not a request-path query — an admin console can scan.

Sequel.migration do
  up do
    alter_table(:account_webauthn_keys) do
      # Text over String so PostgreSQL uses TEXT (unbounded) rather than
      # VARCHAR(255) — a descriptor with a long custom-domain identifier
      # under a subdomain host would fit today, but future descriptor
      # additions must not be quietly truncated.
      add_column :surface_scope, String, text: true, null: true, default: nil
      # Exact RP ID used at registration. Required when a configured related
      # origin verifies a credential from another surface.
      add_column :rp_id, String, null: true, default: nil
    end
  end

  down do
    alter_table(:account_webauthn_keys) do
      drop_column :rp_id
      drop_column :surface_scope
    end
  end
end
