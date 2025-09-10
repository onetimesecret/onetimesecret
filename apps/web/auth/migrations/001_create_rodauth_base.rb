Sequel.migration do
  up do
    # Main accounts table
    create_table(:accounts) do
      primary_key :id
      String :email, null: false
      index :email, unique: true
      Integer :status_id, null: false, default: 1
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      # Additional fields for OneTimeSecret integration
      String :last_login_ip
      DateTime :last_login_at
    end

    # Password hashes (stored separately for security)
    create_table(:account_password_hashes) do
      foreign_key :id, :accounts, primary_key: true
      String :password_hash, null: false
    end

    # Email verification
    create_table(:account_verification_keys) do
      foreign_key :id, :accounts, primary_key: true
      String :key, null: false
      DateTime :requested_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      String :email, null: false
    end

    # Password reset functionality
    create_table(:account_password_reset_keys) do
      foreign_key :id, :accounts, primary_key: true
      String :key, null: false
      DateTime :deadline, null: false
      String :email, null: false
    end

    # Brute force protection
    create_table(:account_login_failures) do
      foreign_key :id, :accounts, primary_key: true
      Integer :number, null: false, default: 1
    end

    # Account lockouts
    create_table(:account_lockouts) do
      foreign_key :id, :accounts, primary_key: true
      String :key, null: false
      DateTime :deadline, null: false
      String :email
    end

    # Remember me functionality
    create_table(:account_remember_keys) do
      foreign_key :id, :accounts, primary_key: true
      String :key, null: false
      DateTime :deadline, null: false
    end

    # Active sessions tracking
    create_table(:account_active_session_keys) do
      foreign_key :account_id, :accounts
      String :session_id, null: false, primary_key: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :last_use, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Add indexes for performance
    add_index :account_verification_keys, :key, unique: true
    add_index :account_password_reset_keys, :key, unique: true
    add_index :account_remember_keys, :key, unique: true
    add_index :account_lockouts, :key, unique: true
    add_index :account_active_session_keys, [:account_id, :session_id], unique: true
    add_index :account_active_session_keys, :last_use
    add_index :accounts, :created_at
    add_index :accounts, :status_id
  end

  down do
    drop_table(:account_active_session_keys)
    drop_table(:account_remember_keys)
    drop_table(:account_lockouts)
    drop_table(:account_login_failures)
    drop_table(:account_password_reset_keys)
    drop_table(:account_verification_keys)
    drop_table(:account_password_hashes)
    drop_table(:accounts)
  end
end
