# apps/web/auth/operations/customers/normalize_account_emails.rb
#
# frozen_string_literal: true

# Loaded from the CLI (outside the auth app's autoloader), so every
# dependency is required explicitly.
require 'onetime/signup_validation'
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
      # address changes). The bytes the scan read are handed to ChangeEmail
      # as `expected_auth_email:`; it re-reads the row before any write and
      # refuses (`:stale`, nothing written) unless the row still holds
      # exactly those bytes, then compare-and-sets on them. A row that moved
      # between scan and apply is therefore reported, not clobbered.
      #
      # ## What it refuses (never merges, never guesses)
      #
      #   :skipped_fold_unstable   canonical form is not fold-stable (ß -> ss):
      #                            the lowercase address is a DIFFERENT address
      #   :skipped_sql_collision   another accounts row (live OR closed) holds
      #                            the canonical address, or canonicalizes to
      #                            it (every member of such a group is skipped)
      #   :skipped_no_customer     no Customer via external_id, the stored
      #                            address, or the canonical address
      #   :skipped_index_collision the Redis email index already maps the
      #                            canonical address to a different Customer
      #                            (the duplicate migration 007 left behind)
      #   :error                   anything else: a canonical form that is not
      #                            structurally a valid address, an external_id
      #                            that names a different extid than the
      #                            Customer holding the address, cross-store
      #                            drift, a row that changed between scan and
      #                            apply
      #
      # A normalized row is not scanned again, so a second run re-does none of
      # them; refused and errored rows are still candidates and are re-reported
      # on every run until an operator resolves them (`after_id:` skips past
      # them on a limited run). Dry run (the default) writes nothing to SQL or
      # Redis — it does not even call ChangeEmail, whose preview records an
      # observation event.
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
        # @!attribute last_account_id [r]
        #   @return [Integer, nil] id of the last candidate this run processed
        #     (candidates are processed in id order), nil when it processed
        #     none. Pass it back as `after_id:` to resume a limited run past
        #     rows it already reported.
        Result = Data.define(:dry_run, :stats, :rows, :last_account_id)

        # @param dry_run [Boolean] report only (default). `false` applies.
        # @param limit [Integer, nil] cap on candidate rows processed; nil = all
        # @param after_id [Integer, nil] process only candidates with
        #   `id > after_id`; nil = from the start. Review item 9: a limited
        #   run otherwise re-reports the same refused low-id rows forever and
        #   never reaches the rest.
        # @param db [Sequel::Database, nil] defaults to Auth::Database.connection
        # @param actor [String] audit actor for the ChangeEmail events
        def initialize(dry_run: true, limit: nil, after_id: nil, db: nil, actor: DEFAULT_ACTOR)
          @dry_run  = dry_run ? true : false
          @limit    = non_negative_integer(limit, 'limit')
          @after_id = non_negative_integer(after_id, 'after_id')
          @actor    = actor
          @db       = db || (defined?(Auth::Database) ? Auth::Database.connection : nil)
          raise Onetime::Problem, 'Auth database unavailable (simple auth mode?)' unless @db
        end

        # @return [Result]
        def call
          stats                                    = { scanned: 0 }
          OUTCOMES.each { |outcome| stats[outcome] = 0 }
          rows                                     = []
          last_account_id                          = nil

          candidate_rows.each do |row|
            report                   = process_row_safely(row)
            stats[:scanned]         += 1
            stats[report[:outcome]] += 1
            rows << report
            last_account_id          = row[:id]
            log_row(report)
          end

          Auth::Logging.log_operation(
            :normalize_account_emails,
            dry_run: @dry_run,
            last_account_id: last_account_id,
            **stats,
          )

          Result.new(dry_run: @dry_run, stats: stats, rows: rows, last_account_id: last_account_id)
        end

        private

        # `Integer()` semantics for junk (raises), plus a floor: a negative
        # cap or cursor has no meaning here.
        def non_negative_integer(value, name)
          return nil if value.nil?

          int = Integer(value)
          raise ArgumentError, "#{name}: must be a non-negative Integer (got #{value.inspect})" if int.negative?

          int
        end

        # ------------------------------------------------------------- scan

        # The candidates this run processes, in id order: every row whose
        # stored address is not already canonical, minus those at or below
        # `after_id`, capped at `limit`.
        #
        # Filtered in Ruby, not SQL: `email != LOWER(email)` is false on a
        # citext column, and SQL lower() is ASCII-only on SQLite and blind to
        # NFC. Keyset-paged, so each page is bounded.
        #
        # The scan is ALWAYS complete — it does not stop at `limit` or start
        # at `after_id` — because collision detection needs every candidate
        # (review item 6): two rows that canonicalize to one address through
        # a mapping lower() cannot see (KELVIN SIGN, Unicode whitespace
        # padding) are invisible to `sql_holders` on SQLite, and a run that
        # stopped scanning at `limit` could normalize the first and leave two
        # canonical-equivalent holders. So every candidate is grouped by its
        # canonical form first, any group with more than one member is
        # remembered (`@canonical_peers`), and only THEN are `after_id` and
        # `limit` applied. Memory is O(candidates): the mixed-case rows only
        # (four small columns each), a small subset of the table, never the
        # table itself.
        #
        # @return [Array<Hash>] { id:, email:, external_id:, status_id: }
        def candidate_rows
          candidates       = all_candidates
          @canonical_peers = candidates
            .group_by { |row| OT::Utils.canonical_email(row[:email].to_s) }
            .select { |_target, rows| rows.size > 1 }

          selected = @after_id ? candidates.select { |row| row[:id] > @after_id } : candidates
          @limit ? selected.first(@limit) : selected
        end

        def all_candidates
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

            batch.each { |row| candidates << row if mixed_case?(row[:email].to_s) }
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
        #   2. target not structurally an address    -> :error
        #   3. another accounts row holds the target
        #      or canonicalizes to it                -> :skipped_sql_collision
        #   4. no Customer resolvable                -> :skipped_no_customer
        #   5. external_id names a different extid   -> :error (ambiguous link)
        #   6. Customer holds a different address    -> :error (drift)
        #   7. index maps target to another Customer -> :skipped_index_collision
        #   8. dry run                               -> :normalized (nothing written)
        #   9. ChangeEmail                           -> :normalized / mapped
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

          # Review item 3: the same structural gate ChangeEmail applies to a
          # same-mailbox rewrite, run here so a dry run and a live run agree
          # (the dry run never calls ChangeEmail).
          unless Onetime::SignupValidation.structurally_valid_email?(target)
            return report(
              row,
              stored,
              target,
              :error,
              'the canonical address is not structurally valid (local@domain.tld without ' \
              'whitespace, commas or semicolons), so ChangeEmail would refuse it; left for the operator',
            )
          end

          holders = collision_holders(row, target)
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
        #
        # `expected_auth_email: stored` is the compare-and-set baseline: the
        # bytes THIS scan read, not whatever ChangeEmail finds when it probes
        # (review items 1/2/4). ChangeEmail refuses with `:stale` before any
        # write when the row is gone or holds other bytes.
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
            expected_auth_email: stored,
            db: @db,
          ).call

          warnings = Array(result.warnings)
          suffix   = warnings.empty? ? '' : " (warnings: #{warnings.join(', ')})"

          case result.status
          when :success
            if result.auth_row_updated
              report(row, stored, target, :normalized, warnings.empty? ? nil : "warnings: #{warnings.join(', ')}")
            else
              # Not expected to be reachable: the row existed at scan time
              # and ChangeEmail refuses (:stale) when it is gone or changed,
              # so a :success here means the Customer hash and indexes WERE
              # rewritten while the accounts row was not. Say so; a "re-run"
              # would find nothing (the stores now disagree, and the row may
              # not even be a candidate any more).
              report(
                row,
                stored,
                target,
                :error,
                'ChangeEmail returned :success with auth_row_updated=false: the Redis Customer ' \
                "record was rewritten to the canonical address but accounts row #{row[:id]} was " \
                "not; the stores may now disagree. Run `bin/ots customers doctor #{customer.extid}`#{suffix}",
              )
            end
          when :stale
            report(
              row,
              stored,
              target,
              :error,
              "accounts row #{row[:id]} is gone or no longer held the scanned address when ChangeEmail " \
              "re-read it (nothing written); the row changed between scan and apply, re-run#{suffix}",
            )
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

        # Every other accounts row that holds the canonical address or
        # canonicalizes to it, from two engine-agnostic sources (review item
        # 6): rows ALREADY canonical come from `sql_holders` (exact equality,
        # which citext also answers case-blind on PostgreSQL), rows still
        # mixed-case come from the Ruby grouping the scan built
        # (`@canonical_peers`). No SQL lower(): it is ASCII-only on SQLite
        # and would miss a KELVIN SIGN or Unicode-whitespace-padded sibling.
        # The two overlap on PostgreSQL (citext matches the mixed-case peers
        # too), hence the de-duplication by id.
        #
        # @return [Array<Hash>] { id:, status_id: }, by id
        def collision_holders(row, target)
          peers = (@canonical_peers || {}).fetch(target, []).reject { |peer| peer[:id] == row[:id] }
          (sql_holders(row[:id], target) + peers.map { |peer| peer.slice(:id, :status_id) })
            .uniq { |holder| holder[:id] }
            .sort_by { |holder| holder[:id] }
        end

        # Other rows holding EXACTLY the canonical address. Closed rows
        # count: ChangeEmail refuses an address a closed account holds for
        # the same reason (#3916).
        #
        # @return [Array<Hash>] { id:, status_id: }
        def sql_holders(own_id, target)
          accounts
            .exclude(id: own_id)
            .where(email: target)
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
