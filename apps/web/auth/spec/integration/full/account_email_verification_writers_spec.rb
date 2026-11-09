# apps/web/auth/spec/integration/full/account_email_verification_writers_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Migration 015 (ADR-051): the accounts row's verification columns
# (email_verified_at, email_verified_by, email_verification_hold) move with
# every verification change, through Auth::AccountEmailVerification, so the
# backfill's one-time copy stays current and `customers doctor`
# (auth_email_verification_drift) reports only a write that failed between
# the stores. Pinned here against the real schema and real Customers:
#
#   * SetCustomerVerification writes them in the UPDATE that sets status_id:
#     proof for a mailbox-proof provenance at the Customer's address, cleared
#     otherwise
#   * a self-service email change clears them in the swap, then records the
#     followed link as 'email' proof in both stores, for an account that was
#     already verified and still is at the write; an unverified account
#     stays unverified
#   * an operator email change leaves them cleared
#
# The after_verify_account hook is pinned in
# full_webauthn_verify/webauthn_verify_account_hook_spec.rb (the lane that
# loads verify_account), the invite signup in
# invite_signup_autologin_internal_request_spec.rb.
#
# Untagged examples run in `full-sqlite` and `full-pg-agnostic`.
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'Migration 015 verification columns follow every writer (ADR-051)', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require 'auth/operations/set_customer_verification'
    require 'auth/operations/customers/change_email'
    require 'auth/operations/customers/doctor'
  end

  let(:db) { Auth::Database.connection }
  let(:accounts) { db[:accounts] }
  let(:run) { SecureRandom.hex(6) }
  let(:email) { "writers-#{run}@example.com" }
  let(:new_email) { "writers-moved-#{run}@example.com" }

  let(:created_account_ids) { [] }
  let(:created_customers) { [] }

  after do
    created_account_ids.each do |id|
      db[:account_active_session_keys].where(account_id: id).delete
      accounts.where(id: id).delete
    end
    created_customers.each do |cust|
      reloaded = Onetime::Customer.load(cust.objid)
      reloaded.destroy! if reloaded&.exists?
    rescue StandardError => ex
      warn "[account_email_verification_writers_spec] customer cleanup failed: #{ex.class}: #{ex.message}"
    end
  end

  def create_customer(address, **)
    cust = Onetime::Customer.create!(email: address, role: 'customer', **)
    created_customers << cust
    cust
  end

  def insert_account(address, customer:, status_id:, **columns)
    id = accounts.insert(email: address, status_id: status_id, external_id: customer.extid, **columns)
    created_account_ids << id
    id
  end

  def account_row(id)
    accounts.where(id: id).first
  end

  def proof_columns(by)
    { email_verified_at: Time.now.utc, email_verified_by: by, email_verification_hold: nil }
  end

  def verification_drift?(customer)
    Auth::Operations::Customers::Doctor.new(customer: customer).call.issues
      .any? { |issue| issue[:check] == :auth_email_verification_drift }
  end

  describe 'SetCustomerVerification' do
    def set_verification(customer, verified:, verified_by:)
      Auth::Operations::SetCustomerVerification.new(
        customer: customer, verified: verified, verified_by: verified_by,
      ).call
    end

    it 'records mailbox proof in the UPDATE that verifies the account' do
      customer = create_customer(email)
      id       = insert_account(email, customer: customer, status_id: Auth::AccountStatuses::UNVERIFIED)

      expect(set_verification(customer, verified: true, verified_by: 'cli_provision')).to eq(:success)

      row = account_row(id)
      expect(row[:status_id]).to eq(Auth::AccountStatuses::VERIFIED)
      expect(row[:email_verified_at]).not_to be_nil
      expect(row[:email_verified_by]).to eq('cli_provision')
      expect(row[:email_verification_hold]).to be_nil
    end

    it 'clears it when it unverifies the account' do
      customer = create_customer(email, verified: true, verified_by: 'cli_provision')
      id       = insert_account(
        email,
        customer: customer,
        status_id: Auth::AccountStatuses::VERIFIED,
        **proof_columns('cli_provision'),
      )

      expect(set_verification(customer, verified: false, verified_by: nil)).to eq(:success)

      row = account_row(id)
      expect(row[:status_id]).to eq(Auth::AccountStatuses::UNVERIFIED)
      expect(row.values_at(:email_verified_at, :email_verified_by, :email_verification_hold)).to all(be_nil)
    end

    it 'records no proof for a provenance that is not mailbox proof (an IdP assertion)' do
      customer = create_customer(email)
      id       = insert_account(email, customer: customer, status_id: Auth::AccountStatuses::UNVERIFIED)

      expect(set_verification(customer, verified: true, verified_by: 'sso')).to eq(:success)

      row = account_row(id)
      expect(row[:status_id]).to eq(Auth::AccountStatuses::VERIFIED)
      expect(row[:email_verified_at]).to be_nil
      expect(row[:email_verified_by]).to be_nil
    end

    it 'records no proof on a row at another address than the Customer' do
      customer = create_customer(email)
      id       = insert_account(
        "elsewhere-#{run}@example.com",
        customer: customer,
        status_id: Auth::AccountStatuses::UNVERIFIED,
      )

      expect(set_verification(customer, verified: true, verified_by: 'cli_provision')).to eq(:success)

      expect(account_row(id)[:email_verified_at]).to be_nil
    end
  end

  describe 'self-service email change (the followed link proved the new address)' do
    def redeem(customer)
      Auth::Operations::Customers::ChangeEmail.new(
        customer: customer,
        new_email: new_email,
        actor: customer.extid,
        dry_run: false,
        require_verification: false,
        revoke_sessions: false,
        notify: false,
        self_service: true,
      ).call
    end

    it "gives a Customer verified by payment 'email' proof in both stores" do
      customer = create_customer(email, verified: true, verified_by: 'stripe_payment')
      id       = insert_account(email, customer: customer, status_id: Auth::AccountStatuses::VERIFIED)
      expect(customer.mailbox_verified?).to be(false)

      expect(redeem(customer).status).to eq(:success)

      reloaded = Onetime::Customer.load(customer.objid)
      expect(reloaded.email).to eq(new_email)
      expect(reloaded.verified_by).to eq('email')
      expect(reloaded.mailbox_verified?).to be(true)
      row      = account_row(id)
      expect(row[:email]).to eq(new_email)
      expect(row[:email_verified_at]).not_to be_nil
      expect(row[:email_verified_by]).to eq('email')
      expect(verification_drift?(reloaded)).to be(false)
    end

    [:sql, :redis].each do |store|
      it "reports recorded proof when the federation recheck cannot read #{store}", :aggregate_failures do
        customer = create_customer(email, verified: true, verified_by: 'sso')
        id = insert_account(email, customer: customer, status_id: Auth::AccountStatuses::VERIFIED)
        events = []
        stamp = nil
        fail_next_read = false
        allow(Onetime::ColonelAuditEvent).to receive(:record_security) { |**event| events << event }
        allow(Auth::Operations::EnsureDefaultWorkspace).to receive(:claim_pending_federation_for)
        allow(Auth::Operations::SetCustomerVerification).to receive(:new).and_wrap_original do |original, **kwargs|
          stamp = original.call(**kwargs)
          allow(stamp).to receive(:confirmed_proof_current?).and_wrap_original do |recheck|
            # Arm the read failure only after both real stamp writes succeeded.
            expect(account_row(id)[:email_verified_by]).to eq('email')
            expect(Onetime::Customer.load(customer.objid).verified_by).to eq('email')
            fail_next_read = true
            recheck.call
          end
          stamp
        end

        reader, method, error = if store == :sql
          [db, :[], Sequel::DatabaseConnectionError]
        else
          [Onetime::Customer, :load, Redis::CannotConnectError]
        end
        allow(reader).to receive(method).and_wrap_original do |original, *args|
          if fail_next_read
            fail_next_read = false
            raise error, "#{store} unavailable during federation recheck"
          end
          original.call(*args)
        end

        result = redeem(customer)

        expect(fail_next_read).to be(false)
        expect(result.status).to eq(:success)
        expect(result.warnings).not_to include(:mailbox_proof_not_recorded)
        audit = events.find { |event| event[:verb] == 'customer.change_email' }
        expect(audit[:detail]).to include(mailbox_proof: :recorded)
        expect(stamp.federation_claimed?).to be(false)
        expect(Auth::Operations::EnsureDefaultWorkspace).not_to have_received(:claim_pending_federation_for)
        expect(account_row(id)).to include(email: new_email, email_verified_by: 'email')
        expect(Onetime::Customer.load(customer.objid).mailbox_verified?).to be(true)
      end
    end

    it 'replaces a stamp that proved the old address' do
      customer = create_customer(email, verified: true, verified_by: 'colonel_admin')
      id       = insert_account(
        email,
        customer: customer,
        status_id: Auth::AccountStatuses::VERIFIED,
        **proof_columns('colonel_admin'),
      )

      expect(redeem(customer).status).to eq(:success)

      expect(Onetime::Customer.load(customer.objid).verified_by).to eq('email')
      expect(account_row(id)[:email_verified_by]).to eq('email')
    end

    # Codex review on 3566f95d1: a self-service change before the login
    # backfill must not lose its proof to the backfill's copy from the
    # mirror. The stamp is in the mirror too, and the backfill leaves
    # columns the mirror agrees with as recorded.
    it 'keeps that proof, with its time, through a later login backfill' do
      require 'auth/operations/backfill_account_logins'
      customer = create_customer(email, verified: true, verified_by: 'sso')
      id       = insert_account(email, customer: customer, status_id: Auth::AccountStatuses::VERIFIED)
      expect(redeem(customer).status).to eq(:success)
      # Backdated, so that a rewrite by the backfill would show.
      recorded_at = Time.utc(2026, 11, 1, 12, 0, 0)
      accounts.where(id: id).update(email_verified_at: recorded_at)

      Auth::Operations::BackfillAccountLogins.new(dry_run: false).call

      row = account_row(id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:email_verified_by]).to eq('email')
      expect(row[:email_verified_at].to_i).to eq(recorded_at.to_i)
    end

    # Codex review on 9284e1c12: the eligibility check reads the status
    # captured before the swap, so an operator who unverifies the account
    # after that read must not see the stamp verify it again.
    it 'leaves an account unverified when an operator unverifies it after the eligibility read' do
      customer = create_customer(email, verified: true, verified_by: 'stripe_payment')
      id       = insert_account(email, customer: customer, status_id: Auth::AccountStatuses::VERIFIED)
      allow_any_instance_of(Auth::Operations::Customers::ChangeEmail)
        .to receive(:record_self_service_proof).and_wrap_original do |original|
          Auth::Operations::SetCustomerVerification.new(
            customer: Onetime::Customer.load(customer.objid), verified: false, verified_by: nil,
          ).call
          original.call
        end

      result = redeem(customer)

      expect(result.status).to eq(:success)
      expect(result.warnings).to include(:mailbox_proof_not_recorded)

      reloaded = Onetime::Customer.load(customer.objid)
      expect(reloaded.verified?).to be(false)
      expect(reloaded.verified_by.to_s).to be_empty
      row      = account_row(id)
      expect(row[:status_id]).to eq(Auth::AccountStatuses::UNVERIFIED)
      expect(row.values_at(:email_verified_at, :email_verified_by, :email_verification_hold)).to all(be_nil)
    end

    it 'does not stamp a concurrent operator address after writing SQL proof for the confirmed address' do
      customer = create_customer(email, verified: true, verified_by: 'sso')
      id       = insert_account(email, customer: customer, status_id: Auth::AccountStatuses::VERIFIED)
      operator_email = "operator-#{run}@example.com"
      allow(Auth::Operations::EnsureDefaultWorkspace).to receive(:claim_pending_federation_for)
      allow_any_instance_of(Auth::Operations::SetCustomerVerification)
        .to receive(:update_rodauth_account!).and_wrap_original do |original|
          result = original.call
          expect(account_row(id)[:email_verified_by]).to eq('email')
          changed = Auth::Operations::Customers::ChangeEmail.new(
            customer: Onetime::Customer.load(customer.objid),
            new_email: operator_email, actor: 'cli', dry_run: false,
            require_verification: false, revoke_sessions: false, notify: false,
          ).call
          expect(changed.status).to eq(:success)
          result
        end

      result = redeem(customer)

      expect(result.status).to eq(:success)
      expect(result.warnings).to include(:mailbox_proof_not_recorded)

      reloaded = Onetime::Customer.load(customer.objid)
      expect(reloaded.email).to eq(operator_email)
      expect(reloaded.verified?).to be(true)
      expect(reloaded.verified_by).to eq('sso')
      expect(reloaded.mailbox_verified?).to be(false)
      expect(account_row(id)).to include(email: operator_email, email_verified_at: nil, email_verified_by: nil)
      expect(Auth::Operations::EnsureDefaultWorkspace).not_to have_received(:claim_pending_federation_for)
    end

    it 'binds the SQL UPDATE itself to the confirmed address, not an earlier address read' do
      customer = create_customer(email, verified: true, verified_by: 'sso')
      id = insert_account(email, customer: customer, status_id: Auth::AccountStatuses::VERIFIED)
      operator_email = "sql-race-#{run}@example.com"
      allow_any_instance_of(Auth::Operations::SetCustomerVerification)
        .to receive(:email_verification_values).and_wrap_original do |original, *args|
          values = original.call(*args)
          accounts.where(id: id).update(email: operator_email, **proof_columns('colonel_admin'))
          values
        end

      expect(redeem(customer).status).to eq(:success)

      expect(account_row(id)).to include(email: operator_email, email_verified_by: 'colonel_admin')
      expect(Onetime::Customer.load(customer.objid).verified_by).to eq('sso')
    end

    it 'does not overwrite an unverify immediately before the Redis write' do
      customer = create_customer(email, verified: true, verified_by: 'sso')
      insert_account(email, customer: customer, status_id: Auth::AccountStatuses::VERIFIED)
      allow(customer.dbclient).to receive(:eval).and_wrap_original do |original, script, **options|
        if script == Auth::Operations::SetCustomerVerification::STAMP_CONFIRMED_EMAIL
          current = Onetime::Customer.load(customer.objid)
          current.verified = false
          current.verified_by = nil
          current.save
        end
        original.call(script, **options)
      end

      expect(redeem(customer).status).to eq(:success)

      current = Onetime::Customer.load(customer.objid)
      expect(current.verified?).to be(false)
      expect(current.verified_by).to be_nil
    end

    it 'does not save stale unrelated fields when the Redis stamp succeeds' do
      customer = create_customer(email, verified: true, verified_by: 'sso')
      insert_account(email, customer: customer, status_id: Auth::AccountStatuses::VERIFIED)
      allow(customer.dbclient).to receive(:eval).and_wrap_original do |original, script, **options|
        if script == Auth::Operations::SetCustomerVerification::STAMP_CONFIRMED_EMAIL
          current = Onetime::Customer.load(customer.objid)
          current.suspended = true
          current.save
        end
        original.call(script, **options)
      end

      expect(redeem(customer).status).to eq(:success)

      current = Onetime::Customer.load(customer.objid)
      expect(current.verified_by).to eq('email')
      expect(current.suspended?).to be(true)
    end

    it 'never recreates a Customer deleted immediately before the Redis stamp' do
      customer = create_customer(email, verified: true, verified_by: 'sso')
      insert_account(email, customer: customer, status_id: Auth::AccountStatuses::VERIFIED)
      allow(customer.dbclient).to receive(:eval).and_wrap_original do |original, script, **options|
        customer.dbclient.del(customer.dbkey) if script == Auth::Operations::SetCustomerVerification::STAMP_CONFIRMED_EMAIL
        original.call(script, **options)
      end

      expect(redeem(customer).status).to eq(:success)
      expect(customer.exists?).to be(false)
    end

    [Auth::AccountStatuses::UNVERIFIED, Auth::AccountStatuses::CLOSED].each do |status|
      it "does not claim federation if SQL becomes status #{status} after the Redis stamp" do
        customer = create_customer(email, verified: true, verified_by: 'sso')
        id = insert_account(email, customer: customer, status_id: Auth::AccountStatuses::VERIFIED)
        allow(Auth::Operations::EnsureDefaultWorkspace).to receive(:claim_pending_federation_for)
        allow_any_instance_of(Auth::Operations::SetCustomerVerification)
          .to receive(:claim_pending_federation!).and_wrap_original do |original|
            accounts.where(id: id).update(status_id: status)
            original.call
          end

        expect(redeem(customer).status).to eq(:success)
        expect(Auth::Operations::EnsureDefaultWorkspace).not_to have_received(:claim_pending_federation_for)
        expect(account_row(id)[:status_id]).to eq(status)
      end
    end

    it 'leaves an unverified account unverified, with the columns cleared' do
      customer = create_customer(email)
      id       = insert_account(email, customer: customer, status_id: Auth::AccountStatuses::UNVERIFIED)

      expect(redeem(customer).status).to eq(:success)

      reloaded = Onetime::Customer.load(customer.objid)
      expect(reloaded.verified?).to be(false)
      row      = account_row(id)
      expect(row[:status_id]).to eq(Auth::AccountStatuses::UNVERIFIED)
      expect(row.values_at(:email_verified_at, :email_verified_by, :email_verification_hold)).to all(be_nil)
      expect(verification_drift?(reloaded)).to be(false)
    end
  end

  describe 'operator email change' do
    it 'clears the columns and the mirror: nobody has proven the new address' do
      customer = create_customer(email, verified: true, verified_by: 'email')
      id       = insert_account(
        email,
        customer: customer,
        status_id: Auth::AccountStatuses::VERIFIED,
        **proof_columns('email'),
      )

      result = Auth::Operations::Customers::ChangeEmail.new(
        customer: customer,
        new_email: new_email,
        actor: 'cli',
        dry_run: false,
        revoke_sessions: false,
        notify: false,
      ).call

      expect(result.status).to eq(:success)
      reloaded = Onetime::Customer.load(customer.objid)
      expect(reloaded.verified?).to be(false)
      row      = account_row(id)
      expect(row[:status_id]).to eq(Auth::AccountStatuses::UNVERIFIED)
      expect(row.values_at(:email_verified_at, :email_verified_by, :email_verification_hold)).to all(be_nil)
      expect(verification_drift?(reloaded)).to be(false)
    end
  end
end
