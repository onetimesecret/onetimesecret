# apps/web/auth/operations/customers/prune_closed_accounts.rb
#
# frozen_string_literal: true

# Loaded from the CLI (outside the auth app's autoloader), so every
# dependency is required explicitly.
require 'auth/account_statuses'
require 'auth/database'
require 'auth/lib/logging'
require 'auth/operations/remove_authentication_data'

module Auth
  module Operations
    module Customers
      # Delete the `accounts` rows that closures left behind, with their
      # authentication audit logs (#4819).
      #
      # ## The problem
      #
      # Until #4819, closing an account (self-service or administrative) set
      # the Rodauth row to CLOSED and kept every
      # account_authentication_audit_logs row for it: the plaintext email plus
      # a per-event record of client IP, user agent and correlation id, with
      # no expiry, for an account whose Customer record was already deleted.
      # Closure now deletes the row and its audit log in the same transaction.
      # This operation removes the rows that predate the change.
      #
      # ## What it does
      #
      # A closed row has no product use: signup ignores it and the partial
      # unique index on accounts.email does not cover it. Every status-3 row
      # is therefore a candidate, whether or not a Customer with the same
      # address exists now (a re-signup created a new row of its own).
      #
      # One kind of closed row still means something. A closure before #4819
      # that stopped after closing the row and before deleting the Customer
      # record (a partial cleanup) left the record behind, and the closed row
      # was its only tombstone: `customers sync-auth-accounts` skips any
      # customer whose extid is on a row. accounts.external_id is unique, so
      # no live row can name such a customer. Before its row is deleted, each
      # Customer a closed row still resolves to gets the closure marker
      # (Customer#mark_closure_started!), dated from the row's updated_at,
      # which the update trigger set when the row closed. The record then
      # reads as an interrupted closure to `customers diagnose` and `doctor`,
      # sync skips it, and `customers finish-closures` purges it. A failed
      # marker write raises and the transaction deletes nothing. Most
      # markers are written before the transaction opens (see #delete_rows),
      # so a run whose transaction rolls back leaves them in place. That is
      # still accurate: each such record is an interrupted closure whether or
      # not its row goes, and a re-run keeps the first marker's time.
      #
      # Dry run (the default) counts and writes nothing. A live run deletes,
      # inside one transaction, every row in
      # RemoveAuthenticationData::DEPENDENT_TABLES that references a closed
      # account (the audit log is the table expected to have rows; the
      # credential tables were cleared at closure, but a row left by an
      # interrupted closure is removed too), then the accounts rows. The
      # closed ids are read once, locked (FOR UPDATE, ignored by SQLite) for
      # the reason given at RemoveAuthenticationData.delete_dependent_rows,
      # and every delete is keyed on that list, so the rows locked and the
      # rows deleted are the same set. The list goes out in slices of
      # DELETE_BATCH ids per statement, which bounds the statement size
      # however large the backlog is. The same statements run on PostgreSQL
      # and SQLite. Re-running is a no-op.
      class PruneClosedAccounts
        # @!attribute dry_run [r]
        #   @return [Boolean]
        # @!attribute accounts [r]
        #   @return [Integer] closed accounts rows found (dry run) or deleted
        # @!attribute rows [r]
        #   @return [Hash{Symbol=>Integer}] dependent rows found or deleted,
        #     per table; only tables with at least one row are listed
        # @!attribute marked [r]
        #   @return [Integer] Customer records a closed row still resolves to,
        #     found (dry run) or marked as closing
        Result = Data.define(:dry_run, :accounts, :rows, :marked)

        # Closed ids per DELETE statement.
        DELETE_BATCH = 500

        # @param dry_run [Boolean] report only (default). `false` deletes.
        # @param db [Sequel::Database, nil] defaults to Auth::Database.connection
        def initialize(dry_run: true, db: nil)
          @dry_run = dry_run ? true : false
          @db      = db || (defined?(Auth::Database) ? Auth::Database.connection : nil)
          raise Onetime::Problem, 'Auth database unavailable (simple auth mode?)' unless @db
        end

        # @return [Result]
        def call
          accounts, rows, marked = @dry_run ? count_rows : delete_rows

          Auth::Logging.log_operation(
            :prune_closed_accounts,
            dry_run: @dry_run,
            accounts: accounts,
            marked: marked,
            **rows,
          )

          Result.new(dry_run: @dry_run, accounts: accounts, rows: rows, marked: marked)
        end

        private

        def closed_accounts
          @db[:accounts].where(status_id: Auth::AccountStatuses::CLOSED)
        end

        # Rows in one dependent table that reference a closed account.
        def dependent_rows(table)
          column = RemoveAuthenticationData.fk_column_for(table)
          @db[table].where(column => closed_accounts.select(:id))
        end

        def dependent_tables
          RemoveAuthenticationData.existing_dependent_tables(@db)
        end

        def count_rows
          rows = dependent_tables.each_with_object({}) do |table, counts|
            count         = dependent_rows(table).count
            counts[table] = count if count.positive?
          end
          [closed_accounts.count, rows, leftover_customers(closed_accounts.select_order_map(:id)).size]
        end

        # The leftover records are resolved and marked before the transaction
        # opens, so its row locks are not held across a Redis round trip per
        # row; only rows that closed in between are marked under the lock.
        def delete_rows
          premarked = closed_accounts.select_order_map(:id)
          marked    = mark_leftover_customers(premarked)
          @db.transaction do
            ids      = closed_accounts.for_update.select_order_map(:id)
            marked  += mark_leftover_customers(ids - premarked)
            tables   = dependent_tables
            rows     = Hash.new(0)
            accounts = ids.each_slice(DELETE_BATCH).sum do |slice|
              tables.each do |table|
                column       = RemoveAuthenticationData.fk_column_for(table)
                rows[table] += @db[table].where(column => slice).delete
              end
              @db[:accounts].where(id: slice).delete
            end
            [accounts, rows.select { |_table, count| count.positive? }, marked]
          end
        end

        # Before the rows go (see the class comment). A failed write raises
        # and nothing is deleted.
        def mark_leftover_customers(ids)
          leftover_customers(ids).count do |customer, closed_at|
            customer.mark_closure_started!(at: closed_at)
          end
        end

        # [customer, closed_at] for every Customer a closed row still names
        # (see the class comment). closed_at is the row's updated_at in epoch
        # seconds (#closed_at_epoch). One pipelined read of the extid index
        # and one load per DELETE_BATCH rows rather than a find_by_extid
        # round trip per row: on the backlog this command exists to clear,
        # the dry run was otherwise the slow half.
        def leftover_customers(ids)
          ids.each_slice(DELETE_BATCH).flat_map do |slice|
            rows      = @db[:accounts].where(id: slice).exclude(external_id: nil).select_map([:external_id, :updated_at])
            customers = customers_by_extid(rows.map(&:first))
            rows.filter_map do |extid, updated_at|
              customer = customers[extid]
              [customer, closed_at_epoch(updated_at)] if customer
            end
          end
        end

        # @return [Hash{String => Onetime::Customer}] the records that exist,
        #   by extid. An extid the index does not know, or whose record is
        #   gone, is absent, as find_by_extid would return nil for it.
        def customers_by_extid(extids)
          return {} if extids.empty?

          # The index stores each identifier serialized; read it back the way
          # the index's own reader (Customer.find_by_extid) does.
          lookup = Onetime::Customer.extid_lookup
          raws   = lookup.dbclient.pipelined do |pipe|
            extids.each { |extid| pipe.hget(lookup.dbkey, extid) }
          end
          objids = raws.map { |raw| raw.nil? ? nil : lookup.deserialize_value(raw) }
          known  = extids.zip(objids).reject { |_extid, objid| objid.to_s.empty? }
          return {} if known.empty?

          known.map(&:first).zip(Onetime::Customer.load_multi(known.map(&:last))).to_h.compact
        end

        # accounts.updated_at is written by the update trigger, in UTC on
        # both databases (Auth::DatabaseConnection.utc_timestamp has the zone
        # rules): on a UTC-7 host, Time#to_i would date the marker seven
        # hours ahead, and Customer.closure_state would read the closure as
        # still in progress until then. Never later than now, so a server
        # that breaks the UTC convention cannot hold it there longer than
        # CLOSURE_STALE_AFTER.
        def closed_at_epoch(updated_at)
          [Auth::DatabaseConnection.utc_timestamp(updated_at).to_i, Familia.now.to_i].min
        end
      end
    end
  end
end
