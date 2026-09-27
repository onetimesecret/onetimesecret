# frozen_string_literal: true

# Exact RP ID used when each WebAuthn credential was registered. Reauthentication
# needs this provenance to select one RP cohort for challenge generation and to
# verify related-origin assertions against the credential's registration RP.
Sequel.migration do
  up do
    alter_table(:account_webauthn_keys) do
      add_column :rp_id, String, null: true, default: nil
    end
  end

  down do
    alter_table(:account_webauthn_keys) do
      drop_column :rp_id
    end
  end
end
