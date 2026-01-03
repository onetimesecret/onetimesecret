# spec/integration/full/initializers/provision_colonels_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ProvisionColonels Initializer - Full Auth Mode', type: :integration do
  include AuthTestConstants

  let(:initializer) { Onetime::Initializers::ProvisionColonels.new }
  let(:test_email) { 'colonel@test.example.com' }
  let(:authdb) { Auth::Database.connection }

  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/auth_config'
    require 'auth/database'
    require 'onetime/initializers/provision_colonels'
    require 'argon2'
  end

  before do
    # Clean Redis
    Familia.dbclient.flushdb

    # Clean authdb tables
    cleanup_all_accounts(db: authdb)
  end

  after do
    # Clean up test data
    Familia.dbclient.flushdb
    cleanup_all_accounts(db: authdb)
  end

  # Note: There is a bug in the implementation where create_rodauth_account
  # tries to insert password_hash directly into accounts table, but the schema
  # requires it to be in account_password_hashes table (separate 1:1 relationship).
  # This causes all provisioning tests to fail with:
  # "SQLite3::SQLException: table accounts has no column named password_hash"
  #
  # The implementation needs to be fixed to:
  # 1. Insert account without password_hash
  # 2. Get the account_id
  # 3. Insert password_hash into account_password_hashes table with id=account_id
  #
  # For now, these tests document the expected behavior once the bug is fixed.

  describe '#provision_colonel_full_mode' do
    context 'Scenario 1: New Colonel Account' do
      it 'creates customer in Redis (maindb)' do
        initializer.send(:provision_colonel_full_mode, test_email)

        expect(Onetime::Customer.email_exists?(test_email)).to be true
        customer = Onetime::Customer.find_by_email(test_email)
        expect(customer.email).to eq(test_email)
        expect(customer.role).to eq('colonel')
      end

      it 'creates account in authdb with status_id=2 (verified)' do
        initializer.send(:provision_colonel_full_mode, test_email)

        account = authdb[:accounts].where(email: test_email).first
        expect(account).not_to be_nil
        expect(account[:status_id]).to eq(AuthTestConstants::STATUS_VERIFIED)
      end

      it 'links customer and account via external_id field' do
        initializer.send(:provision_colonel_full_mode, test_email)

        customer = Onetime::Customer.find_by_email(test_email)
        account = authdb[:accounts].where(email: test_email).first

        expect(account[:external_id]).to eq(customer.extid)
        expect(customer.extid).not_to be_nil
      end

      it 'generates secure password (20 chars, alphanumeric)' do
        # Capture the password from the log output
        allow(initializer).to receive(:log_password) do |email, password|
          @captured_password = password
        end

        initializer.send(:provision_colonel_full_mode, test_email)

        expect(@captured_password).to match(/^[a-zA-Z0-9]{20}$/)
      end

      it 'password is properly hashed with Argon2' do
        allow(initializer).to receive(:log_password) do |email, password|
          @captured_password = password
        end

        initializer.send(:provision_colonel_full_mode, test_email)

        account = authdb[:accounts].where(email: test_email).first
        # Password hash is stored in separate table (Rodauth convention)
        password_row = authdb[:account_password_hashes].where(id: account[:id]).first
        expect(password_row[:password_hash]).to start_with('$argon2')

        # Verify password can be validated (Argon2::Password.verify_password is a class method)
        expect(Argon2::Password.verify_password(@captured_password, password_row[:password_hash])).to be true
      end

      it 'sets verified status in Redis customer' do
        initializer.send(:provision_colonel_full_mode, test_email)

        customer = Onetime::Customer.find_by_email(test_email)
        expect(customer.verified).to eq('true')
      end

      it 'sets verified_by field to auto_provision' do
        initializer.send(:provision_colonel_full_mode, test_email)

        customer = Onetime::Customer.find_by_email(test_email)
        expect(customer.verified_by).to eq('auto_provision')
      end

      it 'logs the generated password' do
        # Allow any log calls, but verify the password-related ones
        allow(OT).to receive(:li)
        expect(OT).to receive(:li).with(/Colonel password for/).ordered
        expect(OT).to receive(:li).with(/Save this password/).ordered

        initializer.send(:provision_colonel_full_mode, test_email)
      end
    end

    context 'Scenario 2: Exists in Both Systems' do
      before do
        # Create customer in Redis
        customer = Onetime::Customer.create!(
          email: test_email,
          role: 'colonel',
          verified: 'true'
        )
        customer.save

        # Create account in authdb
        account_id = authdb[:accounts].insert(
          email: test_email,
          status_id: AuthTestConstants::STATUS_VERIFIED,
          external_id: customer.extid
        )

        password_hash = Argon2::Password.create('existing_password')
        authdb[:account_password_hashes].insert(
          id: account_id,
          password_hash: password_hash
        )
      end

      it 'skips creation when customer and account both exist' do
        expect do
          initializer.send(:provision_colonel_full_mode, test_email)
        end.not_to change { authdb[:accounts].count }
      end

      it 'verifies role is colonel' do
        expect(OT).to receive(:ld).with(/already provisioned in both systems/)

        initializer.send(:provision_colonel_full_mode, test_email)
      end

      it 'logs warning if role mismatch detected' do
        customer = Onetime::Customer.find_by_email(test_email)
        customer.role = 'customer'
        customer.save

        expect(OT).to receive(:lw).with(/expected 'colonel'/)

        initializer.send(:provision_colonel_full_mode, test_email)
      end

      it 'does not generate new password' do
        expect(initializer).not_to receive(:log_password)

        initializer.send(:provision_colonel_full_mode, test_email)
      end
    end

    context 'Scenario 3: Partial State - Redis Only' do
      before do
        # Create only customer in Redis (no SQL account)
        customer = Onetime::Customer.create!(
          email: test_email,
          role: 'customer',  # Wrong role to test update
          verified: 'true'
        )
        customer.save

        @existing_customer_extid = customer.extid
      end

      it 'creates authdb account when customer exists but SQL account missing' do
        expect do
          initializer.send(:provision_colonel_full_mode, test_email)
        end.to change { authdb[:accounts].count }.by(1)
      end

      it 'links via external_id' do
        initializer.send(:provision_colonel_full_mode, test_email)

        account = authdb[:accounts].where(email: test_email).first
        expect(account[:external_id]).to eq(@existing_customer_extid)
      end

      it 'updates role to colonel if needed' do
        expect(OT).to receive(:lw).with(/Updated.*role to colonel/)

        initializer.send(:provision_colonel_full_mode, test_email)

        customer = Onetime::Customer.find_by_email(test_email)
        expect(customer.role).to eq('colonel')
      end

      it 'generates and logs new password' do
        expect(initializer).to receive(:log_password).with(test_email, anything)

        initializer.send(:provision_colonel_full_mode, test_email)
      end

      it 'creates password hash in authdb' do
        initializer.send(:provision_colonel_full_mode, test_email)

        account = authdb[:accounts].where(email: test_email).first
        # Password hash is stored in separate table (Rodauth convention)
        password_row = authdb[:account_password_hashes].where(id: account[:id]).first
        expect(password_row[:password_hash]).to start_with('$argon2')
      end
    end

    context 'Scenario 4: Partial State - SQL Only' do
      before do
        # Create only SQL account (no Redis customer)
        @sql_account_id = authdb[:accounts].insert(
          email: test_email,
          status_id: AuthTestConstants::STATUS_VERIFIED,
          external_id: nil  # Not linked yet
        )

        old_password_hash = Argon2::Password.create('old_password')
        authdb[:account_password_hashes].insert(
          id: @sql_account_id,
          password_hash: old_password_hash
        )
      end

      it 'creates Redis customer when SQL account exists but customer missing' do
        expect(Onetime::Customer.email_exists?(test_email)).to be false

        initializer.send(:provision_colonel_full_mode, test_email)

        expect(Onetime::Customer.email_exists?(test_email)).to be true
      end

      it 'links existing SQL account via external_id' do
        initializer.send(:provision_colonel_full_mode, test_email)

        customer = Onetime::Customer.find_by_email(test_email)
        account = authdb[:accounts].where(id: @sql_account_id).first

        expect(account[:external_id]).to eq(customer.extid)
      end

      it 'updates SQL password hash' do
        # Password hash is stored in separate table (Rodauth convention)
        old_row = authdb[:account_password_hashes].where(id: @sql_account_id).first
        old_hash = old_row[:password_hash]

        initializer.send(:provision_colonel_full_mode, test_email)

        new_row = authdb[:account_password_hashes].where(id: @sql_account_id).first
        new_hash = new_row[:password_hash]
        expect(new_hash).not_to eq(old_hash)
        expect(new_hash).to start_with('$argon2')
      end

      it 'creates customer with colonel role' do
        initializer.send(:provision_colonel_full_mode, test_email)

        customer = Onetime::Customer.find_by_email(test_email)
        expect(customer.role).to eq('colonel')
      end

      it 'sets verified status in Redis customer' do
        initializer.send(:provision_colonel_full_mode, test_email)

        customer = Onetime::Customer.find_by_email(test_email)
        expect(customer.verified).to eq('true')
        expect(customer.verified_by).to eq('auto_provision')
      end

      it 'generates and logs new password' do
        expect(initializer).to receive(:log_password).with(test_email, anything)

        initializer.send(:provision_colonel_full_mode, test_email)
      end
    end

    context 'Edge Cases' do
      describe 'UniqueConstraintViolation handling' do
        # Note: These tests require mocking Sequel datasets which are frozen objects.
        # Rather than skip, we test the actual behavior by triggering the constraint.

        it 'handles race condition when account created between check and insert' do
          # First, create the account so trying to insert again triggers UniqueConstraintViolation
          customer = Onetime::Customer.create!(
            email: test_email,
            role: 'colonel',
            verified: 'true'
          )
          customer.save

          account_id = authdb[:accounts].insert(
            email: test_email,
            status_id: AuthTestConstants::STATUS_VERIFIED,
            external_id: nil
          )

          # Second call should handle the constraint violation gracefully
          expect do
            initializer.send(:create_rodauth_account, authdb, test_email, 'password123', customer.extid)
          end.not_to raise_error

          # Verify external_id was updated
          account = authdb[:accounts].where(id: account_id).first
          expect(account[:external_id]).to eq(customer.extid)
        end

        it 'links existing account when UniqueConstraintViolation occurs' do
          # Create account without external_id
          account_id = authdb[:accounts].insert(
            email: test_email,
            status_id: AuthTestConstants::STATUS_VERIFIED,
            external_id: nil
          )

          customer = Onetime::Customer.create!(
            email: test_email,
            role: 'colonel',
            verified: 'true'
          )
          customer.save

          # Call create_rodauth_account - it will hit UniqueConstraintViolation and recover
          initializer.send(:create_rodauth_account, authdb, test_email, 'password123', customer.extid)

          # Verify external_id was updated
          account = authdb[:accounts].where(id: account_id).first
          expect(account[:external_id]).to eq(customer.extid)
        end
      end

      describe 'Auth database unavailable' do
        it 'logs error and returns early when authdb is nil' do
          allow(Auth::Database).to receive(:connection).and_return(nil)

          expect(OT).to receive(:le).with(/Auth database not available/)

          initializer.send(:provision_colonel_full_mode, test_email)

          # Should not create customer
          expect(Onetime::Customer.email_exists?(test_email)).to be false
        end

        it 'does not fail boot when authdb unavailable' do
          allow(Auth::Database).to receive(:connection).and_return(nil)

          expect do
            initializer.send(:provision_colonel_full_mode, test_email)
          end.not_to raise_error
        end
      end

      describe 'Password logging verification' do
        it 'logs password only once per provision' do
          expect(initializer).to receive(:log_password).once

          initializer.send(:provision_colonel_full_mode, test_email)
        end

        it 'includes warning about saving password' do
          # Allow any log calls, but verify the password warning
          allow(OT).to receive(:li)
          expect(OT).to receive(:li).with(/Save this password/)

          initializer.send(:provision_colonel_full_mode, test_email)
        end

        it 'obscures email in log messages' do
          # Allow any log calls, but verify email obscuring
          # Email obscuring: colonel@test.example.com -> co*****@t*****.com
          allow(OT).to receive(:li)
          expect(OT).to receive(:li).with(/co\*\*\*\*\*@t\*\*\*\*\*\.com/)

          initializer.send(:provision_colonel_full_mode, test_email)
        end
      end

      describe 'Error handling without boot failure' do
        # Note: These tests try to mock OT.conf which is a frozen hash. Skipping until
        # a test-friendly config injection pattern is available.
        it 'catches StandardError in execute method', skip: 'OT.conf is frozen and cannot be mocked' do
          # Mock config to trigger provisioning
          allow(OT.conf).to receive(:dig).with('site', 'authentication').and_return({
            'enabled' => true,
            'colonels' => [test_email]
          })
          allow(Onetime.auth_config).to receive(:mode).and_return('full')

          # Force an error during provisioning
          allow(initializer).to receive(:provision_colonel_full_mode).and_raise(StandardError.new('Test error'))

          expect(OT).to receive(:le).with(/Failed to provision colonel/)

          # Execute should not raise, should log error
          expect do
            initializer.execute({})
          end.not_to raise_error
        end

        it 'logs backtrace in debug mode', skip: 'OT.conf is frozen and cannot be mocked' do
          allow(OT.conf).to receive(:dig).with('site', 'authentication').and_return({
            'enabled' => true,
            'colonels' => [test_email]
          })
          allow(Onetime.auth_config).to receive(:mode).and_return('full')
          allow(OT).to receive(:debug?).and_return(true)

          error = StandardError.new('Test error')
          error.set_backtrace(['line1', 'line2'])
          allow(initializer).to receive(:provision_colonel_full_mode).and_raise(error)

          expect(OT).to receive(:ld).with(/line1/)

          initializer.execute({})
        end
      end
    end

    context 'Password Security' do
      it 'generates different passwords for each call' do
        passwords = []
        allow(initializer).to receive(:log_password) do |email, password|
          passwords << password
        end

        initializer.send(:provision_colonel_full_mode, 'colonel1@test.example.com')
        initializer.send(:provision_colonel_full_mode, 'colonel2@test.example.com')

        expect(passwords[0]).not_to eq(passwords[1])
      end

      it 'generates password with sufficient entropy (20 chars alphanumeric)' do
        allow(initializer).to receive(:log_password) do |email, password|
          @captured_password = password
        end

        initializer.send(:provision_colonel_full_mode, test_email)

        # 20 alphanumeric chars = ~119 bits entropy (log2(62^20))
        expect(@captured_password.length).to eq(20)
        expect(@captured_password).to match(/^[a-zA-Z0-9]{20}$/)
      end

      it 'uses SecureRandom for password generation' do
        expect(SecureRandom).to receive(:alphanumeric).with(20).and_call_original

        initializer.send(:provision_colonel_full_mode, test_email)
      end
    end

    context 'Integration with Rodauth conventions' do
      it 'uses status_id=2 for verified accounts (Rodauth convention)' do
        initializer.send(:provision_colonel_full_mode, test_email)

        account = authdb[:accounts].where(email: test_email).first
        expect(account[:status_id]).to eq(2)
      end

      it 'stores password in account_password_hashes table (not accounts)' do
        initializer.send(:provision_colonel_full_mode, test_email)

        account = authdb[:accounts].where(email: test_email).first
        expect(account[:password_hash]).to be_nil

        # Password should be in separate table
        password_hash_row = authdb[:account_password_hashes].where(id: account[:id]).first
        expect(password_hash_row).not_to be_nil
        expect(password_hash_row[:password_hash]).to start_with('$argon2')
      end

      it 'uses external_id field for linking (Rodauth external_identity feature)' do
        initializer.send(:provision_colonel_full_mode, test_email)

        account = authdb[:accounts].where(email: test_email).first
        expect(account).to have_key(:external_id)
        expect(account[:external_id]).not_to be_nil
      end
    end
  end

  describe '#generate_secure_password' do
    it 'generates 20 character alphanumeric password' do
      password = initializer.send(:generate_secure_password)

      expect(password.length).to eq(20)
      expect(password).to match(/^[a-zA-Z0-9]{20}$/)
    end

    it 'generates unique passwords on each call' do
      password1 = initializer.send(:generate_secure_password)
      password2 = initializer.send(:generate_secure_password)

      expect(password1).not_to eq(password2)
    end
  end

  describe '#create_rodauth_account' do
    let(:customer) do
      cust = Onetime::Customer.create!(
        email: test_email,
        role: 'colonel',
        verified: 'true'
      )
      cust.save
      cust
    end

    it 'creates account with provided email' do
      initializer.send(:create_rodauth_account, authdb, test_email, 'password123', customer.extid)

      account = authdb[:accounts].where(email: test_email).first
      expect(account).not_to be_nil
      expect(account[:email]).to eq(test_email)
    end

    it 'creates account with verified status (status_id=2)' do
      initializer.send(:create_rodauth_account, authdb, test_email, 'password123', customer.extid)

      account = authdb[:accounts].where(email: test_email).first
      expect(account[:status_id]).to eq(AuthTestConstants::STATUS_VERIFIED)
    end

    it 'sets external_id for linking to customer' do
      initializer.send(:create_rodauth_account, authdb, test_email, 'password123', customer.extid)

      account = authdb[:accounts].where(email: test_email).first
      expect(account[:external_id]).to eq(customer.extid)
    end

    it 'hashes password with Argon2' do
      initializer.send(:create_rodauth_account, authdb, test_email, 'password123', customer.extid)

      account = authdb[:accounts].where(email: test_email).first
      # Password hash is stored in separate table (Rodauth convention)
      password_row = authdb[:account_password_hashes].where(id: account[:id]).first
      expect(password_row[:password_hash]).to start_with('$argon2')
    end
  end

  describe '#log_password' do
    it 'logs password with obscured email' do
      # log_password calls OT.li twice - allow both, verify the password one
      # Email obscuring: colonel@test.example.com -> co*****@t*****.com
      allow(OT).to receive(:li)
      expect(OT).to receive(:li).with(/co\*\*\*\*\*@t\*\*\*\*\*\.com.*testpassword/)

      initializer.send(:log_password, test_email, 'testpassword')
    end

    it 'logs warning about saving password' do
      # log_password calls OT.li twice - allow both, verify the warning one
      allow(OT).to receive(:li)
      expect(OT).to receive(:li).with(/Save this password/)

      initializer.send(:log_password, test_email, 'testpassword')
    end
  end
end
