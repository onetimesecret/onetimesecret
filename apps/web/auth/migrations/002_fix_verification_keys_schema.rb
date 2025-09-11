Sequel.migration do
  up do
    # Remove the email column from account_verification_keys as it's not standard Rodauth
    # The email is already available through the foreign key relationship to accounts
    alter_table(:account_verification_keys) do
      drop_column :email
    end

    # Also fix account_password_reset_keys for consistency
    alter_table(:account_password_reset_keys) do
      drop_column :email
    end

    # Fix account_lockouts - email should be nullable since it's not always needed
    if DB.schema(:account_lockouts).any? { |col| col[0] == :email }
      alter_table(:account_lockouts) do
        drop_column :email
      end
    end
  end

  down do
    # Add the columns back if we need to rollback
    alter_table(:account_verification_keys) do
      add_column :email, String, null: false
    end

    alter_table(:account_password_reset_keys) do
      add_column :email, String, null: false
    end

    alter_table(:account_lockouts) do
      add_column :email, String
    end
  end
end
