# apps/web/auth/migrations/006_omniauth_identities.rb
#
# frozen_string_literal: true

# Migration for OmniAuth external identity providers (SSO via OIDC)
# Used by rodauth-omniauth to link external provider identities to accounts

Sequel.migration do
  up do
    create_table(:account_identities) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, null: false, type: :Bignum, on_delete: :cascade
      String :provider, null: false
      String :uid, null: false

      unique [:provider, :uid]
      index :account_id
    end

    case database_type
    when :mysql, :mssql
      user = if database_type == :mysql
        get(Sequel.lit('current_user')).sub(/_password@/, '@')
      else
        get(Sequel.function(:DB_NAME))
      end
      run "GRANT SELECT, INSERT, UPDATE, DELETE ON account_identities TO #{user}"
    end
  end

  down do
    drop_table(:account_identities)
  end
end
