# frozen_string_literal: true
# apps/web/auth/migrations/002_add_external_id.rb
# Add external_id column for Otto's derived identity integration

Sequel.migration do
  up do
    # Add external_id column to accounts table
    alter_table(:accounts) do
      add_column :external_id, String, size: 255
    end

    # Create unique index on external_id
    add_index :accounts, :external_id, unique: true, name: :accounts_external_id_unique
  end

  down do
    # Remove the index first, then the column
    drop_index :accounts, :external_id, name: :accounts_external_id_unique
    alter_table(:accounts) do
      drop_column :external_id
    end
  end
end
