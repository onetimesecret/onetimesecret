# apps/web/auth/operations/customers/normalize_account_emails.rb
#
# frozen_string_literal: true

# Loaded from the CLI (outside the auth app's autoloader), so every
# dependency is required explicitly.
require 'auth/account_statuses'
require 'auth/database'
require 'auth/lib/logging'
require 'auth/operations/customers/change_email'

module Auth
  module Operations
    module Customers
      # Bring every mixed-case `accounts.email` row to its canonical form
      # (#4726), one row at a time, through {ChangeEmail}.
      #
      # ## The problem
      #
      # rodauth-omniauth persisted `omniauth_email` without `normalize_login`,
      # so SSO-provisioned accounts rows kept the identity provider's casing
      # (`Jane.Doe@Example.COM`) while `Customer.create!` keyed the Redis
      # customer email index by the normalized form. PR #4730 canonicalizes
      # the address for NEW sign-ins; rows written before it still carry the
      # provider's bytes, and the nine readers that do a raw, exact
      # `Customer.find_by_email(account[:email])` miss the Customer for them
      # (new-login alerts, MFA, active sessions, teardown, re-auth offers).
      #
      # ## What this does
      #
      # Scans `accounts` for rows whose stored address differs from
      # `OT::Utils.canonical_email(stored)` and, for each, applies the ONE email
      # mutation — `ChangeEmail` with `allow_canonicalization: true` and the
      # user-facing follow-ups off (no verification reset, no session
      # revocation, no notices: nothing a user would recognise as their
      # address changes). The SQL write is compare-and-set on the bytes the
      # scan read, so a row that moved in between is reported, not clobbered.
      #
      # ## What it refuses (never merges, never guesses)
      #
      #   :skipped_fold_unstable   canonical form is not fold-stable (ß -> ss):
      #                            the lowercase address is a DIFFERENT address
      #   :skipped_sql_collision   another accounts row (live OR closed) holds
      #                            the canonical address
      #   :skipped_no_customer     no Customer via external_id, the stored
      #                            address, or the canonical address
      #   :skipped_index_collision the Redis email index already maps the
      #                            canonical address to a different Customer
      #                            (the duplicate migration 007 left behind)
      #   :error                   anything else, including an external_id
      #                            that names a different extid than the
      #                            Customer holding the address, and
      #                            cross-store drift
      #
      # Idempotent: a second run finds nothing. Dry run (the default) writes
      # nothing to SQL or Redis — it does not even call ChangeEmail, whose
      # preview records an observation event.
      class NormalizeAccountEmails
        include Onetime::LoggerMethods

        OUTCOMES = [
          :normalized,
          :skipped_fold_unstable,
          :skipped_sql_collision,
          :skipped_index_collision,
          :skipped_no_customer,
          :error,
        ].freeze

        # Recorded on every `customer.change_email` event this run emits.
        AUDIT_REASON = 'bin/ots customers normalize-emails: canonicalize a mixed-case account email (#4726)'

        # Mirrors Onetime::CLI::Customers::Shared::CLI_ACTOR without depending
        # on the CLI from an operation.
        DEFAULT_ACTOR = 'cli'

        # Keyset page size for the accounts scan.
        BATCH_SIZE = 1000

        # @!attribute dry_run [r]
        #   @return [Boolean]
        # @!attribute stats [r]
        #   @return [Hash{Symbol=>Integer}] :scanned plus one count per OUTCOMES
        # @!attribute rows [r]
        #   @return [Array<Hash>] one per scanned row:
        #     { account_id:, outcome:, from:, to:, detail: } with the
        #     addresses OBSCURED
        Result = Data.define(:dry_run, :stats, :rows)

        # @param dry_run [Boolean] report only (default). `false` applies.
        # @param limit [Integer, nil] cap on mixed-case rows processed; nil = all
        # @param db [Sequel::Database, nil] defaults to Auth::Database.connection
        # @param actor [String] audit actor for the ChangeEmail events
        def initialize(dry_run: true, limit: nil, db: nil, actor: DEFAULT_ACTOR)
          @dry_run = dry_run ? true : false
          @limit   = limit.nil? ? nil : Integer(limit)
          @actor   = actor
          @db      = db || (defined?(Auth::Database) ? Auth::Database.connection : nil)
          raise Onetime::Problem, 'Auth database unavailable (simple auth mode?)' unless @db
        end

        # @return [Result]
        def call
          stats                                    = { scanned: 0 }
          OUTCOMES.each { |outcome| stats[outcome] = 0 }
          rows                                     = []

          candidate_rows.each do |row|
            report                   = process_row_safely(row)
            stats[:scanned]         += 1
            stats[report[:outcome]] += 1
            rows << report
            log_row(report)
          end

          Auth::Logging.log_operation(
            :normalize_account_emails,
            dry_run: @dry_run,
            **stats,
          )

          Result.new(dry_run: @dry_run, stats: stats, rows: rows)
        end

        private

        # ------------------------------------------------------------- scan

        # Every row whose stored address is not already canonical, by id.
        # Filtered in Ruby, not SQL: `email != LOWER(email)` is false on a
        # citext column, and SQL lower() is ASCII-only on SQLite and blind to
        # NFC. Keyset-paged so the scan is bounded in memory and can stop at
        # `limit` without abandoning a server-side cursor.
        #
        # @return [Array<Hash>] { id:, email:, external_id:, status_id: }
        def candidate_rows
          candidates = []
          last_id    = 0

          loop do
            batch = accounts
              .select(:id, :email, :external_id, :status_id)
              .where { id > last_id }
              .order(:id)
              .limit(BATCH_SIZE)
              .all
            break if batch.empty?

            batch.each do |row|
              next unless mixed_case?(row[:email].to_s)

              candidates << row
              return candidates if @limit && candidates.size >= @limit
            end

            last_id = batch.last[:id]
          end

          candidates
        end

        def mixed_case?(stored)
          !stored.empty? && OT::Utils.canonical_email(stored) != stored
        end

        # -------------------------------------------------------------- row

        def process_row_safely(row)
          process_row(row)
        rescue StandardError => ex
          stored = row[:email].to_s
          target = safe_canonical(stored)
          auth_logger.error '[customers.normalize_account_emails] row failed',
            account_id: row[:id],
            exception: ex
          report(row, stored, target, :error, "#{ex.class}: #{scrub(ex.message, stored, target)}")
        end

        # Decision order (every gate runs before any write):
        #   1. fold-unstable canonical form          -> :skipped_fold_unstable
        #   2. another accounts row holds the target -> :skipped_sql_collision
        #   3. no Customer resolvable                -> :skipped_no_customer
        #   4. external_id names a different extid   -> :error (ambiguous link)
        #   5. Customer holds a different address    -> :error (drift)
        #   6. index maps target to another Customer -> :skipped_index_collision
        #   7. dry run                               -> :normalized (nothing written)
        #   8. ChangeEmail                           -> :normalized / mapped
        def process_row(row)
          stored = row[:email].to_s
          target = OT::Utils.canonical_email(stored)

          unless OT::Utils.fold_stable_email?(target)
            return report(
              row,
              stored,
              target,
              :skipped_fold_unstable,
              'case folding would rewrite the address (for example ß -> ss), so the lowercase ' \
              'form is a different address; left for the operator',
            )
          end

          holders = sql_holders(row[:id], target)
          unless holders.empty?
            return report(
              row,
              stored,
              target,
              :skipped_sql_collision,
              "accounts row(s) #{describe_holders(holders)} already hold the canonical address; " \
              'not merged',
            )
          end

          customer = resolve_customer(row, stored, target)
          unless customer
            return report(
              row,
              stored,
              target,
              :skipped_no_customer,
              'no Customer via accounts.external_id, the stored address, or the canonical address',
            )
          end

          # A blank external_id is a known pre-#4726 shape (the row is named to
          # ChangeEmail by id). One that names ANOTHER extid, whose Customer
          # could not be loaded, while a different Customer holds the address
          # is the ambiguous case: left alone.
          linked_extid = row[:external_id].to_s
          if !linked_extid.empty? && linked_extid != customer.extid.to_s
            return report(
              row,
              stored,
              target,
              :error,
              "accounts.external_id names a Customer that could not be loaded while #{customer.extid} " \
              'holds the address; linkage is ambiguous. Run `bin/ots customers sync-auth-accounts` first',
            )
          end

          customer_email = customer.email.to_s
          unless OT::Utils.canonical_email(customer_email) == target
            return report(
              row,
              stored,
              target,
              :error,
              "Customer #{customer.extid} holds #{OT::Utils.obscure_email(customer_email)}, which is not " \
              "a casing of this row's address (cross-store drift); run `bin/ots customers doctor #{customer.extid}`",
            )
          end

          holder = Onetime::Customer.email_index.get(target).to_s
          if !holder.empty? && holder != customer.objid.to_s
            return report(
              row,
              stored,
              target,
              :skipped_index_collision,
              "customer:email_index already maps the canonical address to #{describe_index_holder(holder)}, " \
              "not #{customer.extid}; two customers share one address — merge by hand",
            )
          end

          return report(row, stored, target, :normalized) if @dry_run

          apply(row, customer, stored, target)
        end

        # The single email mutation. Follow-ups a user would notice are off:
        # the address they know does not change. Verification stays (the
        # IdP proved the address), sessions stay, no notices are mailed.
        def apply(row, customer, stored, target)
          result = ChangeEmail.new(
            customer: customer,
            new_email: target,
            actor: @actor,
            dry_run: false,
            require_verification: false,
            revoke_sessions: false,
            notify: false,
            reason: AUDIT_REASON,
            allow_canonicalization: true,
            account_id: row[:id],
            db: @db,
          ).call

          warnings = Array(result.warnings)
          suffix   = warnings.empty? ? '' : " (warnings: #{warnings.join(', ')})"

          case result.status
          when :success
            if result.auth_row_updated
              report(row, stored, target, :normalized, warnings.empty? ? nil : "warnings: #{warnings.join(', ')}")
            else
              report(
                row,
                stored,
                target,
                :error,
                "accounts row #{row[:id]} no longer held the scanned address at write time " \
                "(compare-and-set matched 0 rows); re-run#{suffix}",
              )
            end
          when :email_taken
            report(
              row,
              stored,
              target,
              :skipped_sql_collision,
              'ChangeEmail refused: the canonical address was claimed by another account between ' \
              "scan and write#{suffix}",
            )
          when :partial
            report(
              row,
              stored,
              target,
              :error,
              "ChangeEmail returned :partial (auth_row_updated=#{result.auth_row_updated}); " \
              "run `bin/ots customers doctor #{customer.extid}`#{suffix}",
            )
          else
            report(
              row,
              stored,
              target,
              :error,
              "ChangeEmail returned #{result.status.inspect} " \
              "(auth_row_updated=#{result.auth_row_updated})#{suffix}",
            )
          end
        end

        # ---------------------------------------------------------- lookups

        def accounts
          @db[:accounts]
        end

        # Other rows holding the canonical address. Two predicates because the
        # column differs by engine: citext equality is case-insensitive on
        # PostgreSQL, plain String equality is exact on SQLite, and lower() is
        # ASCII-only there. Closed rows count: ChangeEmail refuses an address
        # a closed account holds for the same reason (#3916).
        #
        # @return [Array<Hash>] { id:, status_id: }
        def sql_holders(own_id, target)
          accounts
            .exclude(id: own_id)
            .where(Sequel.|({ email: target }, { Sequel.function(:lower, :email) => target }))
            .select(:id, :status_id)
            .order(:id)
            .all
        end

        # external_id first (the linkage every other operation keys on), then
        # the exact index under the stored bytes, then under the canonical ones.
        def resolve_customer(row, stored, target)
          extid      = row[:external_id].to_s
          customer   = extid.empty? ? nil : Onetime::Customer.find_by_extid(extid)
          customer ||= Onetime::Customer.find_by_email(stored)
          customer ||= Onetime::Customer.find_by_email(target)
          return nil if customer.nil?
          return nil if customer.respond_to?(:anonymous?) && customer.anonymous?

          customer
        end

        def describe_holders(holders)
          holders.map do |holder|
            status = AccountStatuses::LIVE.include?(holder[:status_id]) ? 'live' : 'closed'
            "#{holder[:id]} (#{status})"
          end.join(', ')
        end

        def describe_index_holder(objid)
          other = Onetime::Customer.find_by_identifier(objid)
          other ? "customer #{other.extid}" : 'a customer record that no longer exists (dangling index entry)'
        rescue StandardError
          'an unloadable customer record'
        end

        # ---------------------------------------------------------- reports

        def report(row, stored, target, outcome, detail = nil)
          {
            account_id: row[:id],
            outcome: outcome,
            from: OT::Utils.obscure_email(stored),
            to: OT::Utils.obscure_email(target),
            detail: detail,
          }
        end

        def safe_canonical(stored)
          OT::Utils.canonical_email(stored)
        rescue StandardError
          stored
        end

        # Exception messages (Sequel includes the statement) can carry the
        # raw address; the report must not.
        def scrub(message, stored, target)
          text = message.to_s
          [stored, target].reject(&:empty?).uniq.each do |raw|
            text = text.gsub(raw, OT::Utils.obscure_email(raw))
          end
          text
        end

        def log_row(report)
          Auth::Logging.log_operation(
            :normalize_account_email,
            level: report[:outcome] == :error ? :error : :info,
            dry_run: @dry_run,
            account_id: report[:account_id],
            outcome: report[:outcome],
            from: report[:from],
            to: report[:to],
            detail: report[:detail],
          )
        end
      end
    end
  end
end
