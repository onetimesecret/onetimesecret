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
      # A closed row has no product use: signup ignores it, the partial unique
      # index on accounts.email does not cover it, and no reader resolves one
      # to a Customer. Every status-3 row is therefore a candidate, whether or
      # not a Customer with the same address exists now (a re-signup created a
      # new row of its own).
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
        Result = Data.define(:dry_run, :accounts, :rows)

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
          accounts, rows = @dry_run ? count_rows : delete_rows

          Auth::Logging.log_operation(
            :prune_closed_accounts,
            dry_run: @dry_run,
            accounts: accounts,
            **rows,
          )

          Result.new(dry_run: @dry_run, accounts: accounts, rows: rows)
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
          [closed_accounts.count, rows]
        end

        def delete_rows
          @db.transaction do
            ids      = closed_accounts.for_update.select_order_map(:id)
            tables   = dependent_tables
            rows     = Hash.new(0)
            accounts = ids.each_slice(DELETE_BATCH).sum do |slice|
              tables.each do |table|
                column       = RemoveAuthenticationData.fk_column_for(table)
                rows[table] += @db[table].where(column => slice).delete
              end
              @db[:accounts].where(id: slice).delete
            end
            [accounts, rows.select { |_table, count| count.positive? }]
          end
        end
      end
    end
  end
end
