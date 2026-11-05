# apps/web/auth/spec/integration/full/backfill_account_logins_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# ADR-051 / SSO email-less accounts Phase 2, step "Backfill op" (design §7).
#
# Drives Auth::Operations::BackfillAccountLogins against the REAL migrated
# accounts schema (migration 015 applied by the suite) and real Valkey
# Customer fixtures. The contract pinned here:
#
#   * `login` becomes the Customer objid and `external_id` its extid, so the
#     two can never disagree; nothing is ever merged and an existing
#     external_id is never rewritten
#   * the verification columns copy the Customer mirror (verified ->
#     email_verified_at + provenance; hold -> email_verification_hold)
#   * dry run writes nothing; a live run is idempotent and resumable
#   * reports never carry the login value
#
# Untagged examples run in `full-sqlite` and `full-pg-agnostic`.
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'Account login backfill (ADR-051)', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require 'auth/operations/backfill_account_logins'
  end

  let(:db) { Auth::Database.connection }
  let(:accounts) { db[:accounts] }
  let(:run) { SecureRandom.hex(6) }
  let(:email) { "backfill-#{run}@example.com" }

  let(:created_account_ids) { [] }
  let(:created_customers) { [] }

  after do
    created_account_ids.each do |id|
      db[:account_active_session_keys].where(account_id: id).delete
      accounts.where(id: id).delete
    end
    created_customers.each do |cust|
      cust.destroy! if cust.exists?
    rescue StandardError => ex
      warn "[backfill_account_logins_spec] customer cleanup failed: #{ex.class}: #{ex.message}"
    end
  end

  def create_customer(email, **kwargs)
    cust = Onetime::Customer.create!(email: email, role: 'customer', **kwargs)
    created_customers << cust
    cust
  end

  def insert_account(email, external_id: nil, status_id: 2)
    id = accounts.insert(email: email, status_id: status_id, external_id: external_id)
    created_account_ids << id
    id
  end

  def account_row(id)
    accounts.where(id: id).first
  end

  def new_operation(**kwargs)
    Auth::Operations::BackfillAccountLogins.new(**kwargs)
  end

  def row_for(result, account_id)
    result.rows.find { |r| r[:account_id] == account_id }
  end

  UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  # ==========================================================================
  # 1. Linked row
  # ==========================================================================

  describe 'linked row (external_id names an existing Customer)' do
    it 'sets login = Customer objid and copies verification from the mirror' do
      customer   = create_customer(email, verified: true, verified_by: 'sso')
      account_id = insert_account(email, external_id: customer.extid)

      result = new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:external_id]).to eq(customer.extid)
      expect(row[:email_verified_at]).not_to be_nil
      expect(row[:email_verified_by]).to eq('sso')
      expect(row[:email_verification_hold]).to be_nil

      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:backfilled)
      expect(report[:branch]).to eq(:by_external_id)
      expect(result.stats).to include(scanned: 1, backfilled: 1, by_external_id: 1)
    end

    it "fills 'legacy' provenance when the verified Customer carries no verified_by" do
      customer   = create_customer(email, verified: true)
      account_id = insert_account(email, external_id: customer.extid)

      new_operation(dry_run: false).call

      expect(account_row(account_id)[:email_verified_by]).to eq('legacy')
    end

    # email_verified_by takes only Onetime::Customer::VERIFIED_BY_VALUES
    # (#4892). A stored tag outside it is a manual decision (the doctor
    # says so too), so the row waits rather than carry the tag into SQL.
    it 'skips a verified Customer whose verified_by is not a known provenance, and writes nothing' do
      customer   = create_customer(email, verified: true, verified_by: 'magic_link_v0')
      account_id = insert_account(email, external_id: customer.extid)
      before     = account_row(account_id)

      result = new_operation(dry_run: false).call

      expect(account_row(account_id)).to eq(before)
      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:skipped_unknown_verified_by)
      expect(report[:detail]).to include('magic_link_v0', 'customers verify')
      expect(result.stats[:skipped_unknown_verified_by]).to eq(1)
    end

    it 'copies every known provenance unchanged' do
      Onetime::Customer::VERIFIED_BY_VALUES.each do |tag|
        customer   = create_customer("#{tag}-#{email}", verified: true, verified_by: tag)
        account_id = insert_account(customer.email, external_id: customer.extid)

        new_operation(dry_run: false).call

        expect(account_row(account_id)[:email_verified_by]).to eq(tag)
      end
    end

    it 'copies a verification hold and leaves email_verified_at NULL' do
      customer   = create_customer(email, verified: false, verification_hold: 'idp_unverified')
      account_id = insert_account(email, external_id: customer.extid)

      new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:email_verified_at]).to be_nil
      expect(row[:email_verified_by]).to be_nil
      expect(row[:email_verification_hold]).to eq('idp_unverified')
    end

    it 'does not mark the mailbox verified when the accounts row is Unverified, whatever the mirror says' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account(email, external_id: customer.extid, status_id: 1)

      new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:email_verified_at]).to be_nil
    end

    # The Customer's verification is proof for the Customer's address. When
    # the row names another address (doctor's :auth_email_drift), copying
    # it would mark a mailbox nobody proved, so the row waits until the
    # stores agree.
    it 'skips the row when the Customer holds a different address, and writes nothing' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account("elsewhere-#{run}@example.com", external_id: customer.extid)
      before     = account_row(account_id)

      result = new_operation(dry_run: false).call

      expect(account_row(account_id)).to eq(before)
      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:skipped_email_mismatch)
      expect(report[:branch]).to eq(:by_external_id)
      expect(report[:detail]).to include(customer.extid, 'auth_email_drift')
      expect(report.to_s).not_to include(email)
      expect(result.stats[:skipped_email_mismatch]).to eq(1)
    end

    it 'treats an address that differs only by case as the same address' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account(email.upcase, external_id: customer.extid)

      new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:email_verified_by]).to eq('email')
    end

    it 'reports exactly the documented stats keys with Integer values' do
      customer = create_customer(email)
      insert_account(email, external_id: customer.extid)

      result = new_operation(dry_run: false).call

      expected = [:scanned] + Auth::Operations::BackfillAccountLogins::OUTCOMES +
                 Auth::Operations::BackfillAccountLogins::BRANCHES
      expect(result.stats.keys).to match_array(expected)
      expect(result.stats.values).to all(be_a(Integer))
    end
  end

  # ==========================================================================
  # 2. Unlinked row
  # ==========================================================================

  describe 'unlinked row (external_id nil, one Customer holds the address)' do
    it 'links the row to that Customer: login = objid, external_id = extid' do
      customer   = create_customer(email)
      account_id = insert_account("Backfill-#{run}@Example.COM", external_id: nil)

      result = new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:external_id]).to eq(customer.extid)
      expect(row_for(result, account_id)[:branch]).to eq(:by_email)
    end

    it 'refuses when another accounts row already links that Customer (never merges)' do
      customer  = create_customer(email)
      linked_id = insert_account(email, external_id: customer.extid)
      # A CLOSED second row holding the same address exists on both backends.
      other_id  = insert_account(email, external_id: nil, status_id: 3)

      result = new_operation(dry_run: false).call

      expect(account_row(linked_id)[:login]).to eq(customer.objid)
      other = account_row(other_id)
      expect(other[:login]).to be_nil
      expect(other[:external_id]).to be_nil
      report = row_for(result, other_id)
      expect(report[:outcome]).to eq(:skipped_customer_linked_elsewhere)
      expect(report[:detail]).to include(linked_id.to_s)
    end
  end

  # ==========================================================================
  # 3. Refusals
  # ==========================================================================

  describe 'dangling external_id' do
    it 'is reported and the link is left untouched' do
      account_id = insert_account(email, external_id: 'urdoesnotexist0000000000000')
      before     = account_row(account_id)

      result = new_operation(dry_run: false).call

      expect(account_row(account_id)).to eq(before)
      expect(row_for(result, account_id)[:outcome]).to eq(:skipped_dangling_external_id)
    end

    # `customers doctor` and `sync-auth-accounts` both start from Customer
    # records, so naming them for a row whose Customer is gone sent the
    # operator nowhere. The detail says which case the row is in.
    it 'names the Customer holding the address, and what re-links the row to it' do
      customer   = create_customer(email)
      account_id = insert_account(email, external_id: 'urdoesnotexist0000000000001')

      detail = row_for(new_operation.call, account_id)[:detail]

      expect(detail).to include(customer.extid, 'next sign-in re-links', 'sync-auth-accounts')
      expect(detail).not_to include('customers doctor')
    end

    it 'says when no Customer holds the address either' do
      account_id = insert_account(email, external_id: 'urdoesnotexist0000000000002')

      detail = row_for(new_operation.call, account_id)[:detail]

      expect(detail).to include('No Customer holds', 'recreates')
      expect(detail).not_to include('customers doctor', 'sync-auth-accounts')
    end

    it 'says when the Customer holding the address is linked by another row' do
      customer   = create_customer(email)
      other_id   = insert_account("other-#{run}@example.com", external_id: customer.extid)
      account_id = insert_account(email, external_id: 'urdoesnotexist0000000000003')

      detail = row_for(new_operation.call, account_id)[:detail]

      expect(detail).to include(customer.extid, "accounts row #{other_id}", 'decide which account keeps')
    end

    it 'points a closed row at prune-closed-accounts' do
      account_id = insert_account(email, external_id: 'urdoesnotexist0000000000004', status_id: 3)

      detail = row_for(new_operation.call, account_id)[:detail]

      expect(detail).to include('closed', 'prune-closed-accounts')
      expect(detail).not_to include('customers doctor')
    end
  end

  describe 'no Customer at all' do
    it 'is skipped by default' do
      account_id = insert_account(email, external_id: nil)

      result = new_operation(dry_run: false).call

      expect(account_row(account_id)[:login]).to be_nil
      expect(row_for(result, account_id)[:outcome]).to eq(:skipped_no_customer)
      expect(result.stats[:skipped_no_customer]).to eq(1)
    end

    # Rodauth status 2 is not mailbox evidence (ADR-051 decision 1): every
    # SSO account opens Verified whatever the IdP said, and a hold lives
    # only on the Customer this row does not have. So a minted row gets no
    # verification columns, whatever its status.
    it 'mints a fresh login and its extid with mint_missing, and leaves a Verified row unverified' do
      account_id = insert_account(email, external_id: nil, status_id: 2)

      result = new_operation(dry_run: false, mint_missing: true).call

      row = account_row(account_id)
      expect(row[:login]).to match(UUID_RE)
      expect(row[:external_id]).to eq(Onetime::Customer.new(objid: row[:login]).extid)
      expect(Onetime::Customer.extid?(row[:external_id])).to be(true)
      expect(row[:email_verified_at]).to be_nil
      expect(row[:email_verified_by]).to be_nil
      expect(row[:email_verification_hold]).to be_nil
      expect(row_for(result, account_id)[:branch]).to eq(:minted)
      expect(row_for(result, account_id)[:detail]).to include('email unverified')
      # Nothing was written to Valkey: the Customer is created by K2 later.
      expect(Onetime::Customer.find_by_extid(row[:external_id])).to be_nil
    end

    it 'leaves a minted Unverified row unverified' do
      account_id = insert_account(email, external_id: nil, status_id: 1)

      new_operation(dry_run: false, mint_missing: true).call

      row = account_row(account_id)
      expect(row[:login]).to match(UUID_RE)
      expect(row[:email_verified_at]).to be_nil
      expect(row[:email_verified_by]).to be_nil
    end
  end

  # ==========================================================================
  # 4. Dry run, idempotence, resumability
  # ==========================================================================

  describe 'dry run' do
    it 'writes nothing and reports what it would do' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account(email, external_id: customer.extid)
      before     = account_row(account_id)

      result = new_operation.call

      expect(result.dry_run).to be(true)
      expect(account_row(account_id)).to eq(before)
      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:backfilled)
      expect(report[:detail]).to include('would set login')
    end
  end

  describe 'idempotence' do
    it 'does not select backfilled rows again' do
      customer = create_customer(email)
      insert_account(email, external_id: customer.extid)

      first  = new_operation(dry_run: false).call
      second = new_operation(dry_run: false).call

      expect(first.stats[:backfilled]).to eq(1)
      expect(second.stats[:scanned]).to eq(0)
      expect(second.last_account_id).to be_nil
    end
  end

  # The decision is made from the scanned row. A sign-in (SyncSession) or
  # `sync-auth-accounts` can re-link the row, a closure can close it, and a
  # change-email can move it, between the scan and the write. Writing
  # anyway would name two Customers on one row (login from the old link,
  # external_id from the new) or copy verification for another address.
  describe 'a row changed between scan and write' do
    def change_row_during_lookup(account_id, **changes)
      allow(Onetime::Customer).to receive(:find_by_extid).and_wrap_original do |original, *args|
        found = original.call(*args)
        accounts.where(id: account_id).update(**changes)
        found
      end
    end

    it 'writes nothing when external_id was re-linked to another Customer' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      other      = create_customer("other-#{run}@example.com")
      account_id = insert_account(email, external_id: customer.extid)
      change_row_during_lookup(account_id, external_id: other.extid)

      result = new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to be_nil
      expect(row[:external_id]).to eq(other.extid)
      expect(row[:email_verified_at]).to be_nil

      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:error)
      expect(report[:detail]).to include('changed between scan and write')
    end

    it 'writes nothing when the address changed' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account(email, external_id: customer.extid)
      change_row_during_lookup(account_id, email: "moved-#{run}@example.com")

      new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to be_nil
      expect(row[:email_verified_at]).to be_nil
    end

    it 'writes nothing when the status changed' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account(email, external_id: customer.extid)
      change_row_during_lookup(account_id, status_id: 3)

      new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to be_nil
      expect(row[:email_verified_at]).to be_nil
    end
  end

  describe 'limit and after_id' do
    it 'processes the lowest ids first and resumes past last_account_id' do
      c1  = create_customer("one-#{run}@example.com")
      c2  = create_customer("two-#{run}@example.com")
      id1 = insert_account(c1.email, external_id: c1.extid)
      id2 = insert_account(c2.email, external_id: c2.extid)

      first = new_operation(dry_run: false, limit: 1).call
      expect(first.rows.map { |r| r[:account_id] }).to eq([id1])
      expect(first.last_account_id).to eq(id1)
      expect(account_row(id2)[:login]).to be_nil

      second = new_operation(dry_run: false, limit: 1, after_id: first.last_account_id).call
      expect(second.rows.map { |r| r[:account_id] }).to eq([id2])
      expect(account_row(id2)[:login]).to eq(c2.objid)
    end
  end

  # ==========================================================================
  # 5. The login value never leaves the database
  # ==========================================================================

  describe 'a row that raises' do
    # A database exception message carries the statement's values (PG's
    # DETAIL line names the duplicate key). Neither the report nor any log
    # line may carry the raw address or the login.
    it 'logs and reports only the scrubbed message, never the exception' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account(email, external_id: customer.extid)
      message    = "PG::UniqueViolation: Key (email, login)=(#{email}, #{customer.objid}) already exists"
      allow(Onetime::Customer).to receive(:find_by_extid).and_raise(Sequel::DatabaseError, message)

      logged = []
      op     = new_operation(dry_run: false)
      logger = instance_double(SemanticLogger::Logger)
      allow(logger).to receive(:error) { |*args| logged << args }
      allow(op).to receive(:auth_logger).and_return(logger)
      allow(Auth::Logging).to receive(:log_operation) { |*args, **kwargs| logged << [args, kwargs] }

      result = op.call

      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:error)
      expect(report[:detail]).to include('Sequel::DatabaseError', OT::Utils.obscure_email(email), '<login>')
      expect(logged).not_to be_empty
      expect(logged.inspect).not_to include(email)
      expect(logged.inspect).not_to include(customer.objid)
      expect(logger).to have_received(:error).with(anything, hash_including(account_id: account_id))
    end
  end

  describe 'reports' do
    it 'carry the obscured email and never the login value' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account(email, external_id: customer.extid)

      result = new_operation(dry_run: false).call

      report = row_for(result, account_id)
      expect(report[:email]).to eq(OT::Utils.obscure_email(email))
      expect(report.to_s).not_to include(customer.objid)
      expect(report.to_s).not_to include(email)
    end
  end
end
