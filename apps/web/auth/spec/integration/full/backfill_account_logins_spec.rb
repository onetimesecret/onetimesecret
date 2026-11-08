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
#   * the verification columns record mailbox proof only: Rodauth VERIFIED,
#     Customer#mailbox_verified? (Onetime::Customer::MAILBOX_VERIFIED_BY) and
#     the Customer holding the row's address; a hold is copied; anything
#     else, a minted row included, stays NULL
#   * an email-index entry naming a Customer at another address links
#     nothing (skipped_index_mismatch)
#   * the write is a compare-and-set on the row as the scan read it
#   * dry run writes nothing; a live run is idempotent and resumable
#   * reports and log lines never carry the login value or the raw address
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
  let(:uuid_re) { /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}\z/ }

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

  def create_customer(email, **)
    cust = Onetime::Customer.create!(email: email, role: 'customer', **)
    created_customers << cust
    cust
  end

  def insert_account(email, external_id: nil, status_id: 2, **columns)
    id = accounts.insert(email: email, status_id: status_id, external_id: external_id, **columns)
    created_account_ids << id
    id
  end

  def account_row(id)
    accounts.where(id: id).first
  end

  def new_operation(**)
    Auth::Operations::BackfillAccountLogins.new(**)
  end

  def row_for(result, account_id)
    result.rows.find { |r| r[:account_id] == account_id }
  end

  # ==========================================================================
  # 1. Linked row
  # ==========================================================================

  describe 'linked row (external_id names an existing Customer)' do
    it 'sets login = Customer objid and copies mailbox proof from the mirror' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account(email, external_id: customer.extid)

      result = new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:external_id]).to eq(customer.extid)
      expect(row[:email_verified_at]).not_to be_nil
      expect(row[:email_verified_by]).to eq('email')
      expect(row[:email_verification_hold]).to be_nil

      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:backfilled)
      expect(report[:branch]).to eq(:by_external_id)
      expect(result.stats).to include(scanned: 1, backfilled: 1, by_external_id: 1)
    end

    it 'copies exactly the MAILBOX_VERIFIED_BY provenances and leaves every other one NULL' do
      tags = Onetime::Customer::VERIFIED_BY_VALUES
      ids  = tags.each_with_index.to_h do |tag, i|
        address  = "prov#{i}-#{run}@example.com"
        customer = create_customer(address, verified: true, verified_by: tag)
        [tag, insert_account(address, external_id: customer.extid)]
      end

      new_operation(dry_run: false).call

      tags.each do |tag|
        row = account_row(ids[tag])
        expect(row[:login]).not_to be_nil, "#{tag}: login not set"
        if Onetime::Customer::MAILBOX_VERIFIED_BY.include?(tag)
          expect(row[:email_verified_by]).to eq(tag), "#{tag} is mailbox proof and should be copied"
          expect(row[:email_verified_at]).not_to be_nil
        else
          expect(row[:email_verified_at]).to be_nil, "#{tag} is not mailbox proof (ADR-051) and must stay NULL"
          expect(row[:email_verified_by]).to be_nil
        end
      end
    end

    it "leaves the columns NULL for a verified Customer with no verified_by (no 'legacy' stamp is minted)" do
      customer   = create_customer(email, verified: true)
      account_id = insert_account(email, external_id: customer.extid)

      new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:email_verified_at]).to be_nil
      expect(row[:email_verified_by]).to be_nil
    end

    it 'leaves the columns NULL when the Customer holds another address (proof for a different mailbox)' do
      customer   = create_customer("other-#{run}@example.com", verified: true, verified_by: 'email')
      account_id = insert_account(email, external_id: customer.extid)

      result = new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:email_verified_at]).to be_nil
      expect(row[:email_verified_by]).to be_nil
      expect(row[:email_verification_hold]).to be_nil
      expect(row_for(result, account_id)[:detail]).to include('email unverified')
    end

    it 'matches the address through normalize_email, as the Customer email index does' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account("Backfill-#{run}@Example.COM", external_id: customer.extid)

      new_operation(dry_run: false).call

      expect(account_row(account_id)[:email_verified_by]).to eq('email')
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

    # A writer that ran after migration 015 (SetCustomerVerification, the
    # verify hook, a self-service email change) wrote the columns with the
    # mirror. The backfill leaves columns the mirror agrees with as they are,
    # so the proof time stays the writer's.
    it 'keeps the proof a writer already recorded for the address, with its time' do
      recorded_at = Time.utc(2026, 11, 1, 12, 0, 0)
      customer    = create_customer(email, verified: true, verified_by: 'email')
      account_id  = insert_account(
        email,
        external_id: customer.extid,
        email_verified_at: recorded_at,
        email_verified_by: 'email',
      )

      result = new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:email_verified_by]).to eq('email')
      expect(row[:email_verified_at].to_i).to eq(recorded_at.to_i)
      expect(row_for(result, account_id)[:detail]).to include('email_verified_by=email (as recorded)')
    end

    it 'replaces columns the Customer mirror does not support: the mirror is what every reader uses' do
      customer   = create_customer(email, verified: true, verified_by: 'sso')
      account_id = insert_account(
        email,
        external_id: customer.extid,
        email_verified_at: Time.utc(2026, 11, 1),
        email_verified_by: 'email',
      )

      new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:email_verified_at]).to be_nil
      expect(row[:email_verified_by]).to be_nil
    end

    it 'does not mark the mailbox verified when the accounts row is Unverified, whatever the mirror says' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account(email, external_id: customer.extid, status_id: 1)

      new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:email_verified_at]).to be_nil
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

    it 'never links a closed row beside the linked live row to that Customer (never merges)' do
      customer  = create_customer(email)
      linked_id = insert_account(email, external_id: customer.extid)
      # A CLOSED second row holding the same address exists on both backends.
      other_id  = insert_account(email, external_id: nil, status_id: 3)

      result = new_operation(dry_run: false).call

      expect(account_row(linked_id)[:login]).to eq(customer.objid)
      other  = account_row(other_id)
      expect(other[:login]).to be_nil
      expect(other[:external_id]).to be_nil
      expect(row_for(result, other_id)[:outcome]).to eq(:skipped_closed_row)
    end
  end

  # A closed row can share a live row's address (the unique index on
  # accounts.email covers LIVE rows only), and it normally has the lower id,
  # so the scan reaches it first.
  describe 'closed unlinked row' do
    it 'does not take the Customer when it precedes the live unlinked row at the same address' do
      customer  = create_customer(email, verified: true, verified_by: 'email')
      closed_id = insert_account(email, external_id: nil, status_id: 3)
      live_id   = insert_account(email, external_id: nil, status_id: 2)
      expect(closed_id).to be < live_id

      result = new_operation(dry_run: false).call

      closed = account_row(closed_id)
      expect(closed[:login]).to be_nil
      expect(closed[:external_id]).to be_nil
      expect(row_for(result, closed_id)[:outcome]).to eq(:skipped_closed_row)

      live = account_row(live_id)
      expect(live[:login]).to eq(customer.objid)
      expect(live[:external_id]).to eq(customer.extid)
      expect(live[:email_verified_by]).to eq('email')
      expect(row_for(result, live_id)).to include(outcome: :backfilled, branch: :by_email)
    end

    it 'does not take the Customer when no live row holds the address either' do
      create_customer(email)
      closed_id = insert_account(email, external_id: nil, status_id: 3)

      result = new_operation(dry_run: false).call

      expect(account_row(closed_id)[:login]).to be_nil
      expect(row_for(result, closed_id)[:outcome]).to eq(:skipped_closed_row)
      expect(result.stats[:skipped_closed_row]).to eq(1)
    end

    it 'gets a fresh login, not the Customer, with mint_missing' do
      customer  = create_customer(email, verified: true, verified_by: 'email')
      closed_id = insert_account(email, external_id: nil, status_id: 3)

      result = new_operation(dry_run: false, mint_missing: true).call

      row = account_row(closed_id)
      expect(row[:login]).to match(uuid_re)
      expect(row[:login]).not_to eq(customer.objid)
      expect(row[:external_id]).to eq(Onetime::Customer.new(objid: row[:login]).extid)
      expect(row[:email_verified_at]).to be_nil
      expect(row_for(result, closed_id)).to include(outcome: :backfilled, branch: :minted)
    end
  end

  # normalize_email case-FOLDS, and folding rewrites `ß` to `ss`, so
  # `straße` and `strasse` are different addresses with one folded form.
  describe 'fold-unstable address' do
    let(:unstable) { "u-#{run}@straße.example.com" }
    let(:folded) { "u-#{run}@strasse.example.com" }

    it 'is never linked by email to the Customer under the folded address' do
      customer = create_customer(folded)
      expect(customer.email).to eq(folded)
      account_id = insert_account(unstable, external_id: nil)

      result = new_operation(dry_run: false, mint_missing: true).call

      row = account_row(account_id)
      expect(row[:login]).to be_nil
      expect(row[:external_id]).to be_nil
      expect(row_for(result, account_id)[:outcome]).to eq(:skipped_fold_unstable)
      expect(result.stats[:skipped_fold_unstable]).to eq(1)
    end

    it 'does not copy proof from a linked Customer whose address differs only by folding' do
      customer   = create_customer(folded, verified: true, verified_by: 'email')
      account_id = insert_account(unstable, external_id: customer.extid)

      new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(customer.objid)
      expect(row[:email_verified_at]).to be_nil
      expect(row[:email_verified_by]).to be_nil
    end

    it 'does not name the Customer under the folded address in a dangling-link report' do
      customer   = create_customer(folded)
      account_id = insert_account(unstable, external_id: 'urdoesnotexist0000000000000')

      result = new_operation(dry_run: false).call

      detail = row_for(result, account_id)[:detail]
      expect(detail).not_to include(customer.extid)
      expect(detail).to include('orphaned')
    end
  end

  # An email index entry still naming a Customer that has since moved to
  # another address (`customers doctor --all` reports it as
  # email_index_mismatch). The row must not take that Customer's login: a
  # linked row is never a candidate again.
  describe 'stale email index entry' do
    let(:moved) { "moved-#{run}@example.com" }
    let(:stale_keys) { [] }

    after do
      stale_keys.each { |key| Onetime::Customer.email_index.remove_field(key) }
    end

    def point_index_at(address, customer)
      Onetime::Customer.email_index[address] = customer.objid
      stale_keys << address
    end

    it 'never links the row to the Customer the stale entry names, mint_missing or not' do
      customer = create_customer(moved)
      point_index_at(email, customer)
      account_id = insert_account(email, external_id: nil)

      result = new_operation(dry_run: false, mint_missing: true).call

      row = account_row(account_id)
      expect(row[:login]).to be_nil
      expect(row[:external_id]).to be_nil
      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:skipped_index_mismatch)
      expect(report[:detail]).to include(customer.extid, 'bin/ots customers doctor --all --repair')
      expect(result.stats[:skipped_index_mismatch]).to eq(1)
    end

    it 'links the Customer at that address when a stale entry names another casing of it' do
      holder = create_customer(email)
      mover  = create_customer(moved)
      stored = email.sub('backfill-', 'Backfill-')
      point_index_at(stored, mover)
      account_id = insert_account(stored, external_id: nil)

      result = new_operation(dry_run: false).call

      row = account_row(account_id)
      expect(row[:login]).to eq(holder.objid)
      expect(row[:external_id]).to eq(holder.extid)
      expect(row_for(result, account_id)).to include(outcome: :backfilled, branch: :by_email)
    end
  end

  # ==========================================================================
  # 3. Refusals
  # ==========================================================================

  describe 'dangling external_id' do
    let(:dangling_extid) { 'urdoesnotexist0000000000000' }

    it 'is reported and the link is left untouched' do
      account_id = insert_account(email, external_id: dangling_extid)
      before     = account_row(account_id)

      result = new_operation(dry_run: false).call

      expect(account_row(account_id)).to eq(before)
      expect(row_for(result, account_id)[:outcome]).to eq(:skipped_dangling_external_id)
    end

    it 'names the Customer that holds the address, which sync-auth-accounts re-links' do
      customer   = create_customer(email)
      account_id = insert_account(email, external_id: dangling_extid)

      result = new_operation(dry_run: false).call

      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:skipped_dangling_external_id)
      expect(report[:detail]).to include(customer.extid)
      expect(report[:detail]).to include('sync-auth-accounts')
      expect(account_row(account_id)[:external_id]).to eq(dangling_extid)
    end

    it 'reports an orphaned row (no Customer under the address) with the account-id diagnosis' do
      account_id = insert_account(email, external_id: dangling_extid)

      result = new_operation(dry_run: false).call

      detail = row_for(result, account_id)[:detail]
      expect(detail).to include("bin/ots customers diagnose #{account_id}")
      expect(detail).to include('orphaned')
      expect(detail).not_to include('sync-auth-accounts')
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

    it 'mints a fresh login and its extid with mint_missing, and leaves the verification columns NULL' do
      account_id = insert_account(email, external_id: nil, status_id: 2)

      result = new_operation(dry_run: false, mint_missing: true).call

      row    = account_row(account_id)
      expect(row[:login]).to match(uuid_re)
      expect(row[:external_id]).to eq(Onetime::Customer.new(objid: row[:login]).extid)
      expect(Onetime::Customer.extid?(row[:external_id])).to be(true)
      # Rodauth status alone is not mailbox proof: there is no Customer, so
      # there is no provenance to copy (ADR-051).
      expect(row[:email_verified_at]).to be_nil
      expect(row[:email_verified_by]).to be_nil
      expect(row[:email_verification_hold]).to be_nil
      report = row_for(result, account_id)
      expect(report[:branch]).to eq(:minted)
      expect(report[:detail]).to include('email unverified')
      # Nothing was written to Valkey: the Customer is created by K2 later.
      expect(Onetime::Customer.find_by_extid(row[:external_id])).to be_nil
    end
  end

  # ==========================================================================
  # 4. Compare-and-set
  # ==========================================================================

  describe 'compare-and-set on the row as scanned' do
    it 'skips a row whose external_id was re-linked between scan and write, and links it on the next run' do
      old_customer = create_customer(email)
      new_customer = create_customer("relinked-#{run}@example.com")
      account_id   = insert_account(email, external_id: old_customer.extid)

      # sync-auth-accounts (or link-on-login) repairs the link after the
      # scan read the row and before the write runs.
      relinked = false
      allow(Onetime::Customer).to receive(:find_by_extid).and_wrap_original do |original, extid|
        unless relinked
          relinked = true
          accounts.where(id: account_id).update(external_id: new_customer.extid)
        end
        original.call(extid)
      end

      result = new_operation(dry_run: false).call

      row    = account_row(account_id)
      expect(row[:login]).to be_nil
      expect(row[:external_id]).to eq(new_customer.extid)
      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:skipped_row_changed)
      expect(report[:branch]).to eq(:by_external_id)
      expect(result.stats[:skipped_row_changed]).to eq(1)

      second = new_operation(dry_run: false).call

      expect(row_for(second, account_id)[:outcome]).to eq(:backfilled)
      expect(account_row(account_id)[:login]).to eq(new_customer.objid)
    end

    it 'skips a row whose verification columns a writer changed between scan and write' do
      customer   = create_customer(email, verified: true, verified_by: 'sso')
      account_id = insert_account(email, external_id: customer.extid)

      # A verification writer records proof after the scan read the row and
      # before the write runs. The mirror this run maps from says 'sso' (no
      # proof), so a write would clear what the writer just recorded.
      allow(Onetime::Customer).to receive(:find_by_extid).and_wrap_original do |original, extid|
        accounts.where(id: account_id).update(email_verified_at: Time.now.utc, email_verified_by: 'email')
        original.call(extid)
      end

      result = new_operation(dry_run: false).call

      expect(row_for(result, account_id)[:outcome]).to eq(:skipped_row_changed)
      row = account_row(account_id)
      expect(row[:login]).to be_nil
      expect(row[:email_verified_by]).to eq('email')
    end

    it 'skips a row whose status changed between scan and write (the verification decision is stale)' do
      customer   = create_customer(email, verified: true, verified_by: 'email')
      account_id = insert_account(email, external_id: customer.extid, status_id: 1)

      allow(Onetime::Customer).to receive(:find_by_extid).and_wrap_original do |original, extid|
        accounts.where(id: account_id).update(status_id: 2)
        original.call(extid)
      end

      result = new_operation(dry_run: false).call

      expect(row_for(result, account_id)[:outcome]).to eq(:skipped_row_changed)
      row = account_row(account_id)
      expect(row[:login]).to be_nil
      expect(row[:email_verified_at]).to be_nil
    end
  end

  # ==========================================================================
  # 5. Dry run, idempotence, resumability
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
  # 6. The login value and the raw address never leave the database
  # ==========================================================================

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

  describe 'error path' do
    it 'reports and logs a failing row with the address and the login value scrubbed, never the exception itself' do
      customer   = create_customer(email)
      account_id = insert_account(email, external_id: customer.extid)
      # What a database error carries: the statement, with its literal values.
      statement  = "UPDATE accounts SET login = '#{customer.objid}' WHERE email = '#{email}'"
      allow(Onetime::Customer).to receive(:find_by_extid).and_raise(Sequel::DatabaseError, statement)

      logged = []
      logger = double('auth_logger')
      allow(logger).to receive(:error) { |*args| logged << args }
      op = new_operation(dry_run: false)
      allow(op).to receive(:auth_logger).and_return(logger)

      result = op.call

      report = row_for(result, account_id)
      expect(report[:outcome]).to eq(:error)
      expect(report[:detail]).to start_with('Sequel::DatabaseError')
      expect(report[:detail]).not_to include(email)
      expect(report[:detail]).not_to include(customer.objid)
      expect(account_row(account_id)[:login]).to be_nil

      expect(logged.size).to eq(1)
      dump = logged.inspect
      expect(dump).to include('row failed')
      expect(dump).not_to include('#<Sequel::DatabaseError')
      expect(dump).not_to include(email)
      expect(dump).not_to include(customer.objid)
    end
  end
end
