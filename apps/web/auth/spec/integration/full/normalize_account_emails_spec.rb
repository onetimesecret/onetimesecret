# apps/web/auth/spec/integration/full/normalize_account_emails_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #4726 — operator-run repair of legacy SSO-provisioned `accounts` rows
# whose email kept the identity provider's casing.
#
# PR #4730 fixed NEW sign-ins (SyncSession tries the stored address before the
# normalized one). Rows provisioned before it still hold `Jane.Doe@Example.COM`
# in SQL while `Customer.create!` keyed the Redis email index by the lowercase
# address. `Onetime::Customer.find_by_email` is an exact-match HGET, so every
# production reader that does `Customer.find_by_email(account[:email])` with
# the SQL casing (login.rb new-login alert, reauth_offer.rb,
# active_sessions.rb, teardown_account.rb, ...) misses the Customer.
#
# Drives Auth::Operations::Customers::NormalizeAccountEmails against the REAL
# migrated accounts schema (Auth::Database.connection) and real Valkey
# Customer fixtures. The correctness rail is the reader contract those call
# sites rely on: after a live run, `Customer.find_by_email(<SQL email>)`
# resolves the row's Customer.
#
# Untagged examples run in `full-sqlite` and `full-pg-agnostic`. The one
# fixture that needs two LIVE rows differing only by case cannot exist on
# PostgreSQL (accounts.email is citext with a partial unique index on live
# statuses) and is skipped there at runtime.
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'Account email normalization repair (#4726)', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    # Lazily required by the CLI, not autoloaded; needs the app booted.
    require 'auth/operations/customers/normalize_account_emails'
  end

  let(:db) { Auth::Database.connection }
  let(:accounts) { db[:accounts] }
  let(:email_index) { Onetime::Customer.email_index }
  let(:run) { SecureRandom.hex(6) }

  # Mixed-case fixture and its canonical form. The local part carries the run
  # id so the obscuring assertions have a raw token to look for.
  let(:local) { "Mixed-Case-#{run}" }
  let(:mixed) { "#{local}@Example.COM" }
  let(:target) { OT::Utils.canonical_email(mixed) }

  # Belt-and-suspenders cleanup; the auth spec_helper flushes Valkey and clears
  # the auth DB around every :integration example, but the datastore is shared
  # so every fixture this file creates is also removed explicitly.
  let(:created_account_ids) { [] }
  let(:created_customers) { [] }
  let(:seeded_index_keys) { [] }

  after do
    created_account_ids.each do |id|
      db[:account_active_session_keys].where(account_id: id).delete
      accounts.where(id: id).delete
    end
    seeded_index_keys.each { |key| email_index.remove_field(key) }
    created_customers.each do |cust|
      cust.destroy! if cust.exists?
    rescue StandardError => ex
      warn "[normalize_account_emails_spec] customer cleanup failed: #{ex.class}: #{ex.message}"
    end
  end

  # ==========================================================================
  # Fixture helpers
  # ==========================================================================

  # A Customer the way every current signup path creates one: normalized,
  # index keyed by the lowercase address.
  def create_customer(email)
    cust = Onetime::Customer.create!(email: email, role: 'customer')
    created_customers << cust
    cust
  end

  # A pre-normalization Customer: the hash holds the address AS GIVEN and
  # Familia's auto-index on save keys the email index by that raw value.
  def create_raw_customer(email)
    cust = Onetime::Customer.new(email: email, role: 'customer')
    cust.save
    created_customers << cust
    seeded_index_keys << email
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

  def sql_email(id)
    accounts.where(id: id).get(:email)
  end

  def index_snapshot
    Familia.dbclient.hgetall(email_index.dbkey)
  end

  def new_operation(dry_run: true, limit: nil, after_id: nil)
    Auth::Operations::Customers::NormalizeAccountEmails.new(dry_run: dry_run, limit: limit, after_id: after_id)
  end

  def row_for(result, account_id)
    result.rows.find { |r| r[:account_id] == account_id }
  end

  let(:stat_keys) do
    %i[
      scanned normalized skipped_fold_unstable skipped_sql_collision
      skipped_index_collision skipped_no_customer error
    ]
  end

  # ==========================================================================
  # 1. Happy path, linked row
  # ==========================================================================

  describe 'linked row (external_id -> lowercase Customer)' do
    it 'lowercases the SQL email and makes the row resolvable by Customer.find_by_email' do
      customer   = create_customer(target)
      account_id = insert_account(mixed, external_id: customer.extid)

      # The bug: the reader contract the nine call sites rely on misses today.
      expect(Onetime::Customer.find_by_email(sql_email(account_id))).to be_nil

      result = new_operation(dry_run: false).call

      expect(result.dry_run).to be(false)
      expect(sql_email(account_id)).to eq(target)
      resolved = Onetime::Customer.find_by_email(sql_email(account_id))
      expect(resolved).not_to be_nil
      expect(resolved.extid).to eq(customer.extid)

      row = row_for(result, account_id)
      expect(row[:outcome]).to eq(:normalized)
      expect(result.stats).to include(scanned: 1, normalized: 1)
    end

    it 'reports exactly the documented stats keys with Integer values' do
      customer = create_customer(target)
      insert_account(mixed, external_id: customer.extid)

      result = new_operation(dry_run: false).call

      expect(result.stats.keys).to match_array(stat_keys)
      expect(result.stats.values).to all(be_a(Integer))
    end
  end

  # ==========================================================================
  # 2. Happy path, unlinked row
  # ==========================================================================

  describe 'unlinked row (external_id nil, Customer under the lowercase key)' do
    it 'resolves the Customer by the canonical index key and normalizes' do
      customer   = create_customer(target)
      account_id = insert_account(mixed, external_id: nil)

      result = new_operation(dry_run: false).call

      expect(row_for(result, account_id)[:outcome]).to eq(:normalized)
      expect(sql_email(account_id)).to eq(target)
      expect(Onetime::Customer.find_by_email(target)&.extid).to eq(customer.extid)
    end
  end

  # ==========================================================================
  # 3. Legacy index row (mixed-case key, no lowercase key)
  # ==========================================================================

  describe 'legacy index row (index keyed by the stored casing only)' do
    it 're-keys the Customer under the canonical address' do
      customer   = create_raw_customer(mixed)
      account_id = insert_account(mixed, external_id: nil)
      expect(email_index.get(mixed)).to eq(customer.objid)
      expect(email_index.get(target)).to be_nil

      result = new_operation(dry_run: false).call

      expect(row_for(result, account_id)[:outcome]).to eq(:normalized)
      expect(sql_email(account_id)).to eq(target)
      resolved = Onetime::Customer.find_by_email(target)
      expect(resolved&.objid).to eq(customer.objid)
      expect(resolved.email).to eq(target)
      # The stale key is gone, or at worst still points at the same Customer.
      expect([nil, customer.objid]).to include(email_index.get(mixed))
    end
  end

  # ==========================================================================
  # 4. SQL collision
  # ==========================================================================

  describe 'SQL collision (another accounts row lowercases to the same target)' do
    it 'skips the mixed-case row, naming the colliding account, and touches neither' do
      customer   = create_customer(target)
      account_id = insert_account(mixed, external_id: customer.extid)
      # A CLOSED holder of the target address: exists on both backends (the
      # citext partial unique index only covers live statuses on PostgreSQL)
      # and is still a collision for every email-keyed lookup.
      other_id   = insert_account(target, external_id: nil, status_id: 3)
      before_mixed = account_row(account_id)
      before_other = account_row(other_id)

      result = new_operation(dry_run: false).call

      row = row_for(result, account_id)
      expect(row[:outcome]).to eq(:skipped_sql_collision)
      expect(row[:detail]).to be_a(String)
      expect(row[:detail]).to include(other_id.to_s)
      expect(result.stats[:skipped_sql_collision]).to eq(1)
      expect(result.stats[:normalized]).to eq(0)
      expect(account_row(account_id)).to eq(before_mixed)
      expect(account_row(other_id)).to eq(before_other)
    end

    it 'skips when the colliding row is LIVE (SQLite only; citext forbids the fixture on PostgreSQL)' do
      skip 'accounts.email is citext with a live-status unique index on PostgreSQL' if db.database_type == :postgres

      customer   = create_customer(target)
      account_id = insert_account(mixed, external_id: customer.extid)
      other_id   = insert_account(target, external_id: nil, status_id: 2)

      result = new_operation(dry_run: false).call

      row = row_for(result, account_id)
      expect(row[:outcome]).to eq(:skipped_sql_collision)
      expect(row[:detail]).to include(other_id.to_s)
      expect(sql_email(account_id)).to eq(mixed)
      expect(sql_email(other_id)).to eq(target)
    end

    # Two rows that canonicalize to ONE address through a mapping SQL
    # lower() cannot see (KELVIN SIGN U+212A -> 'k'; ASCII-only lower() on
    # SQLite leaves it alone). Neither row holds the target exactly, so an
    # equality probe misses both and a lower() probe misses the second.
    # The grouping is done in Ruby over the whole candidate set, BEFORE
    # `limit` applies, so a `--limit 1` run cannot normalize the first row
    # and leave two canonical-equivalent holders behind.
    context 'when the colliding row canonicalizes to the target through a non-ASCII mapping' do
      let(:kelvin_target) { "kelvin-#{run}@example.com" }
      let(:kelvin_ascii) { "Kelvin-#{run}@Example.COM" }
      let(:kelvin_sign) { "Kelvin-#{run}@example.com" }

      it 'skips BOTH members, naming the other, even with limit: 1' do
        expect(OT::Utils.canonical_email(kelvin_sign)).to eq(kelvin_target)
        customer  = create_customer(kelvin_target)
        first_id  = insert_account(kelvin_ascii, external_id: customer.extid)
        # Closed, so the PostgreSQL live-status partial unique index allows
        # it; still a collision for every email-keyed lookup.
        second_id = insert_account(kelvin_sign, external_id: nil, status_id: 3)
        before_first  = account_row(first_id)
        before_second = account_row(second_id)

        limited = new_operation(dry_run: false, limit: 1).call

        expect(limited.stats[:scanned]).to eq(1)
        limited_row = row_for(limited, first_id)
        expect(limited_row[:outcome]).to eq(:skipped_sql_collision)
        expect(limited_row[:detail]).to include("#{second_id} (closed)")
        expect(account_row(first_id)).to eq(before_first)
        expect(account_row(second_id)).to eq(before_second)

        full = new_operation(dry_run: false).call

        expect(full.stats).to include(scanned: 2, skipped_sql_collision: 2, normalized: 0)
        expect(row_for(full, first_id)[:detail]).to include("#{second_id} (closed)")
        expect(row_for(full, second_id)[:detail]).to include("#{first_id} (live)")
        expect(account_row(first_id)).to eq(before_first)
        expect(account_row(second_id)).to eq(before_second)
      end
    end
  end

  # ==========================================================================
  # 4b. Concurrent change between scan and apply
  # ==========================================================================

  describe 'row changed between scan and apply' do
    # The scan reads the row, then the user (or another operator) changes the
    # address before ChangeEmail runs. The repair must report it and leave
    # the user's NEW address in place — never compare-and-set on whatever the
    # probe finds and revert them to the canonical form of the OLD one.
    it 'is reported as :error and the concurrent new address survives in both stores' do
      customer   = create_customer(target)
      account_id = insert_account(mixed, external_id: customer.extid)
      moved_to   = "moved-#{run}@example.com"
      operation  = new_operation(dry_run: false)

      allow(Auth::Operations::Customers::ChangeEmail).to receive(:new).and_wrap_original do |original, **kwargs|
        # Lands after the scan read `mixed`, before the mutation probes.
        accounts.where(id: account_id).update(email: moved_to)
        original.call(**kwargs)
      end
      before_hash  = Familia.dbclient.hgetall(customer.dbkey)
      before_index = index_snapshot

      result = operation.call

      row = row_for(result, account_id)
      expect(row[:outcome]).to eq(:error)
      expect(row[:detail]).to include('between scan and apply')
      expect(result.stats).to include(scanned: 1, error: 1, normalized: 0)
      expect(sql_email(account_id)).to eq(moved_to)
      expect(Familia.dbclient.hgetall(customer.dbkey)).to eq(before_hash)
      expect(index_snapshot).to eq(before_index)
      expect(Auth::Operations::Customers::ChangeEmail).to have_received(:new).with(
        hash_including(account_id: account_id, expected_auth_email: mixed)
      )
    end
  end

  # ==========================================================================
  # 4c. Internationalized addresses
  # ==========================================================================

  describe 'non-ASCII mixed-case row' do
    # `EmailFormat.valid_format?` is ASCII-only; before review item 3 this row
    # passed the dry run and failed live with :invalid_email on every run.
    it 'normalizes on a live run' do
      intl_mixed  = "JOSÉ-#{run}@Example.COM"
      intl_target = OT::Utils.canonical_email(intl_mixed)
      expect(intl_target).to eq("josé-#{run}@example.com")
      customer   = create_customer(intl_target)
      account_id = insert_account(intl_mixed, external_id: customer.extid)

      preview = new_operation.call
      expect(row_for(preview, account_id)[:outcome]).to eq(:normalized)

      result = new_operation(dry_run: false).call

      row = row_for(result, account_id)
      expect(row[:outcome]).to eq(:normalized)
      expect(sql_email(account_id)).to eq(intl_target)
      expect(Onetime::Customer.find_by_email(sql_email(account_id))&.extid).to eq(customer.extid)
    end

    it 'reports a structurally invalid canonical form as :error on the dry run too' do
      skip 'accounts.valid_email CHECK refuses the fixture on PostgreSQL' if db.database_type == :postgres

      broken     = "Dotless-#{run}@localhost"
      account_id = insert_account(broken, external_id: nil)
      before_row = account_row(account_id)

      preview = new_operation.call
      expect(row_for(preview, account_id)[:outcome]).to eq(:error)
      expect(row_for(preview, account_id)[:detail]).to include('not structurally valid')

      result = new_operation(dry_run: false).call

      expect(row_for(result, account_id)[:outcome]).to eq(:error)
      expect(account_row(account_id)).to eq(before_row)
    end
  end

  # ==========================================================================
  # 5. Index collision
  # ==========================================================================

  describe 'index collision (lowercase key already names a different Customer)' do
    it 'skips, names the other Customer, and leaves SQL and the index unchanged' do
      customer_b = create_customer(target)              # owns the lowercase key
      customer_a = create_raw_customer(mixed)           # the row's own Customer
      account_id = insert_account(mixed, external_id: customer_a.extid)
      before_row   = account_row(account_id)
      before_index = index_snapshot

      result = new_operation(dry_run: false).call

      row = row_for(result, account_id)
      expect(row[:outcome]).to eq(:skipped_index_collision)
      expect(row[:detail]).to be_a(String)
      expect(row[:detail]).to include(customer_b.extid)
      expect(result.stats[:skipped_index_collision]).to eq(1)
      expect(account_row(account_id)).to eq(before_row)
      expect(index_snapshot).to eq(before_index)
      expect(email_index.get(target)).to eq(customer_b.objid)
    end
  end

  # ==========================================================================
  # 6. Fold-unstable target
  # ==========================================================================

  describe 'fold-unstable address' do
    it 'skips an address that case folding would rewrite and leaves it untouched' do
      unstable   = "User-#{run}@straße.example.com"
      lowered    = OT::Utils.canonical_email(unstable)
      expect(OT::Utils.fold_stable_email?(lowered)).to be(false)
      customer   = create_raw_customer(unstable)
      account_id = insert_account(unstable, external_id: customer.extid)
      before_row = account_row(account_id)

      result = new_operation(dry_run: false).call

      expect(row_for(result, account_id)[:outcome]).to eq(:skipped_fold_unstable)
      expect(result.stats[:skipped_fold_unstable]).to eq(1)
      expect(account_row(account_id)).to eq(before_row)
      expect(email_index.get(unstable)).to eq(customer.objid)
    end
  end

  # ==========================================================================
  # 7. No customer
  # ==========================================================================

  describe 'no resolvable Customer' do
    it 'skips a row with no external_id and no index entry under either key' do
      account_id = insert_account(mixed, external_id: nil)
      before_row = account_row(account_id)
      expect(email_index.get(mixed)).to be_nil
      expect(email_index.get(target)).to be_nil

      result = new_operation(dry_run: false).call

      expect(row_for(result, account_id)[:outcome]).to eq(:skipped_no_customer)
      expect(result.stats[:skipped_no_customer]).to eq(1)
      expect(account_row(account_id)).to eq(before_row)
    end
  end

  # ==========================================================================
  # 8. Dry-run purity
  # ==========================================================================

  describe 'dry run (default)' do
    it 'reports the would-be outcomes and leaves SQL and Redis byte-for-byte unchanged' do
      customer      = create_customer(target)
      normalizable  = insert_account(mixed, external_id: customer.extid)
      orphan        = insert_account("Orphan-#{run}@Example.COM", external_id: nil)
      other_cust    = create_customer("collide-#{run}@example.com")
      colliding     = insert_account("Collide-#{run}@Example.COM", external_id: other_cust.extid)
      closed_holder = insert_account("collide-#{run}@example.com", external_id: nil, status_id: 3)

      before_rows  = accounts.order(:id).all
      before_index = index_snapshot
      before_hash  = Familia.dbclient.hgetall(customer.dbkey)

      result = new_operation.call

      expect(result.dry_run).to be(true)
      expect(row_for(result, normalizable)[:outcome]).to eq(:normalized)
      expect(row_for(result, orphan)[:outcome]).to eq(:skipped_no_customer)
      expect(row_for(result, colliding)[:outcome]).to eq(:skipped_sql_collision)
      expect(row_for(result, colliding)[:detail]).to include(closed_holder.to_s)
      expect(result.stats).to include(scanned: 3, normalized: 1, skipped_no_customer: 1, skipped_sql_collision: 1)

      expect(accounts.order(:id).all).to eq(before_rows)
      expect(index_snapshot).to eq(before_index)
      expect(Familia.dbclient.hgetall(customer.dbkey)).to eq(before_hash)
      expect(Onetime::Customer.find_by_email(mixed)).to be_nil
    end

    it 'is the default when dry_run: is not given' do
      customer   = create_customer(target)
      account_id = insert_account(mixed, external_id: customer.extid)

      result = Auth::Operations::Customers::NormalizeAccountEmails.new.call

      expect(result.dry_run).to be(true)
      expect(sql_email(account_id)).to eq(mixed)
    end
  end

  # ==========================================================================
  # 9. Idempotency
  # ==========================================================================

  describe 'idempotency' do
    it 'scans and normalizes nothing on a second live run' do
      customer   = create_customer(target)
      account_id = insert_account(mixed, external_id: customer.extid)

      first = new_operation(dry_run: false).call
      expect(first.stats).to include(scanned: 1, normalized: 1)

      second = new_operation(dry_run: false).call
      expect(second.stats).to include(scanned: 0, normalized: 0)
      expect(second.rows).to be_empty
      expect(sql_email(account_id)).to eq(target)
      expect(Onetime::Customer.find_by_email(target)&.extid).to eq(customer.extid)
    end
  end

  # ==========================================================================
  # 10. Already-lowercase rows are out of scope
  # ==========================================================================

  describe 'already-canonical rows' do
    it 'does not scan a row whose email is already its canonical form' do
      customer   = create_customer("already-#{run}@example.com")
      account_id = insert_account(customer.email, external_id: customer.extid)
      before_row = account_row(account_id)

      result = new_operation(dry_run: false).call

      expect(result.stats[:scanned]).to eq(0)
      expect(result.rows).to be_empty
      expect(account_row(account_id)).to eq(before_row)
    end
  end

  # ==========================================================================
  # 11. Sessions survive a case-only repair
  # ==========================================================================

  describe 'sessions' do
    # RevokeAllForCustomer clears Customer#active_sessions, marks each tracked
    # sid ended (SessionEnded.mark), and deletes the account's Rodauth
    # account_active_session_keys rows. A case-only repair must do none of it.
    it 'does not revoke the repaired customer\'s sessions' do
      customer   = create_customer(target)
      account_id = insert_account(mixed, external_id: customer.extid)
      sid        = SecureRandom.hex(16)
      customer.active_sessions.add(sid, Familia.now)
      db[:account_active_session_keys].insert(account_id: account_id, session_id: "rodauth-#{run}")

      result = new_operation(dry_run: false).call

      expect(row_for(result, account_id)[:outcome]).to eq(:normalized)
      expect(customer.active_sessions.member?(sid)).to be(true)
      expect(Onetime::SessionEnded.ended?(sid)).to be(false)
      expect(db[:account_active_session_keys].where(account_id: account_id).count).to eq(1)
    end
  end

  # ==========================================================================
  # 12. limit:
  # ==========================================================================

  describe 'limit:' do
    it 'caps the number of rows processed' do
      ids = 3.times.map do |i|
        cust = create_customer("limit-#{i}-#{run}@example.com")
        insert_account("Limit-#{i}-#{run}@Example.COM", external_id: cust.extid)
      end

      result = new_operation(dry_run: false, limit: 2).call

      expect(result.stats[:scanned]).to eq(2)
      expect(result.rows.size).to eq(2)
      expect(result.rows.map { |r| r[:account_id] } - ids).to be_empty
      normalized = ids.count { |id| sql_email(id) == sql_email(id).downcase }
      expect(normalized).to eq(2)
    end
  end

  # ==========================================================================
  # 12b. after_id: and last_account_id (resume a limited run)
  # ==========================================================================

  describe 'after_id: and last_account_id' do
    it 'skips candidates at or below after_id and reports the last id processed' do
      ids = 3.times.map do |i|
        cust = create_customer("resume-#{i}-#{run}@example.com")
        insert_account("Resume-#{i}-#{run}@Example.COM", external_id: cust.extid)
      end
      ids.sort!

      first = new_operation(dry_run: false, limit: 1).call
      expect(first.rows.map { |r| r[:account_id] }).to eq([ids[0]])
      expect(first.last_account_id).to eq(ids[0])

      second = new_operation(dry_run: false, after_id: first.last_account_id).call

      expect(second.rows.map { |r| r[:account_id] }).to eq(ids[1..])
      expect(second.stats).to include(scanned: 2, normalized: 2)
      expect(second.last_account_id).to eq(ids[2])
      ids.each { |id| expect(sql_email(id)).to eq(sql_email(id).downcase) }
    end

    it 'reports last_account_id nil when nothing was processed' do
      result = new_operation.call

      expect(result.last_account_id).to be_nil
    end

    it 'refuses a negative after_id or limit' do
      expect { new_operation(after_id: -1) }.to raise_error(ArgumentError, /after_id/)
      expect { new_operation(limit: -1) }.to raise_error(ArgumentError, /limit/)
    end
  end

  # ==========================================================================
  # 13. Error isolation
  # ==========================================================================

  describe 'per-row error isolation' do
    it 'reports a lost compare-and-set (ChangeEmail :stale) as :error and leaves the row for a re-run' do
      cust  = create_customer(target)
      id    = insert_account(mixed, external_id: cust.extid)
      stale = Auth::Operations::Customers::ChangeEmail::Result.new(
        status: :stale, extid: cust.extid, from: target, to: target, dry_run: false,
        auth_row_updated: false, orgs_reindexed: 0, sessions_revoked: false,
        verification_reset: false, warnings: [],
      )
      allow(Auth::Operations::Customers::ChangeEmail).to receive(:new)
        .and_return(instance_double(Auth::Operations::Customers::ChangeEmail, call: stale))

      result = new_operation(dry_run: false).call

      row = row_for(result, id)
      expect(row[:outcome]).to eq(:error)
      expect(row[:detail]).to include('re-run')
      expect(sql_email(id)).to eq(mixed)
      expect(result.stats[:error]).to eq(1)
    end

    it 'records one row as :error with detail and still normalizes the others' do
      healthy_cust = create_customer(target)
      healthy      = insert_account(mixed, external_id: healthy_cust.extid)
      victim_cust  = create_customer("victim-#{run}@example.com")
      victim       = insert_account("Victim-#{run}@Example.COM", external_id: victim_cust.extid)

      allow(Onetime::Customer).to receive(:find_by_extid).and_wrap_original do |original, extid|
        raise 'boom: simulated datastore failure' if extid == victim_cust.extid

        original.call(extid)
      end

      result = new_operation(dry_run: false).call

      error_row = row_for(result, victim)
      expect(error_row[:outcome]).to eq(:error)
      expect(error_row[:detail]).to be_a(String)
      expect(error_row[:detail]).to include('boom')
      expect(sql_email(victim)).to eq("Victim-#{run}@Example.COM")

      expect(row_for(result, healthy)[:outcome]).to eq(:normalized)
      expect(sql_email(healthy)).to eq(target)
      expect(result.stats).to include(scanned: 2, normalized: 1, error: 1)
    end
  end

  # ==========================================================================
  # 14. Obscured addresses in the report
  # ==========================================================================

  describe 'report rows' do
    it 'carries obscured from/to addresses, never the raw local part' do
      customer   = create_customer(target)
      account_id = insert_account(mixed, external_id: customer.extid)

      result = new_operation(dry_run: false).call
      row    = row_for(result, account_id)

      expect(row[:account_id]).to be_a(Integer)
      expect(row[:from]).to eq(OT::Utils.obscure_email(mixed))
      expect(row[:to]).to eq(OT::Utils.obscure_email(target))
      expect(row[:from]).not_to include(local)
      expect(row[:to]).not_to include(local.downcase)
      expect(row[:from]).to include('***')
      expect(row[:to]).to include('***')
    end

    it 'obscures the addresses on a dry run too' do
      customer   = create_customer(target)
      account_id = insert_account(mixed, external_id: customer.extid)

      row = row_for(new_operation.call, account_id)

      expect(row[:from]).not_to include(local)
      expect(row[:to]).not_to include(local.downcase)
    end
  end
end
