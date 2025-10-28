# frozen_string_literal: true

Sequel.migration do
  up do
    # Table for base feature
    create_table?(:accounts) do
      primary_key :id, type: :Bignum
      String :email, null: false
      Integer :status, null: false, default: 1
      String :external_id, null: false
      index :external_id, unique: true
      index :email, unique: true, where: { status: [1, 2] }
    end

    # Table for account_webauthn_keys feature
    create_table?(:account_webauthn_keys) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :webauthn_id, null: false
      String :public_key, text: true
      Integer :sign_count, null: false, default: 0
      Time :last_use, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :account_id
      index :webauthn_id
    end

    # Table for account_webauthn_user_ids feature
    create_table(:account_webauthn_user_ids) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :webauthn_id, null: false
      index :account_id
      index :webauthn_id
    end

    # Table for account_email_auth_keys feature
    create_table(:account_email_auth_keys) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :key, null: false
      DateTime :deadline, null: false
      String :email, null: false
      index :account_id
      index :key
    end

    # Table for account_recovery_codes feature
    create_table(:account_recovery_codes) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :code, null: false
      index :account_id
      index :code
    end

    # Table for account_otp_keys feature
    create_table(:account_otp_keys) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :key, null: false
      Integer :num_failures, null: false, default: 0
      Time :last_use, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :account_id
    end

    # Table for account_remember_keys feature
    create_table(:account_remember_keys) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :key, null: false
      DateTime :deadline, null: false
      index :account_id
      index :key
    end

    # Table for account_active_session_keys feature
    create_table(:account_active_session_keys) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :session_id, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      Time :last_activity_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :account_id
      index :session_id
    end

    # Table for lockout feature
    create_table(:account_login_failures) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      Integer :number, null: false, default: 0
      index :account_id
    end

    # Table for lockout feature
    create_table(:account_lockouts) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      DateTime :deadline, null: false
      DateTime :email_last_sent
      index :account_id
    end

    # Table for account_password_reset_keys feature
    create_table(:account_password_reset_keys) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :key, null: false
      DateTime :deadline, null: false
      String :email, null: false
      index :account_id
      index :key
    end

    # Table for account_verification_keys feature
    create_table(:account_verification_keys) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :key, null: false
      DateTime :requested_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      String :email, null: false
      index :account_id
      index :key
    end

    create_table(:account_password_hashes) do
      primary_key :id, type: :Bignum
      Integer :account_id, null: false
      String :key, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :account_id
    end
  end

  down do
    drop_table?(:account_password_hashes)
    drop_table?(:account_verification_keys)
    drop_table?(:account_password_reset_keys)
    drop_table?(:account_lockouts)
    drop_table?(:account_login_failures)
    drop_table?(:account_active_session_keys)
    drop_table?(:account_remember_keys)
    drop_table?(:account_otp_keys)
    drop_table?(:account_recovery_codes)
    drop_table?(:account_email_auth_keys)
    drop_table?(:account_webauthn_user_ids)
    drop_table?(:account_webauthn_keys)
    drop_table?(:accounts)
  end
end
