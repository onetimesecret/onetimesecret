# apps/web/auth/operations/backfill_account_logins.rb
#
# frozen_string_literal: true

# Loaded from the CLI (outside the auth app's autoloader), so every
# dependency is required explicitly.
require 'securerandom'
require 'auth/account_statuses'
require 'auth/database'
require 'auth/lib/logging'

module Auth
  module Operations
    # Give every `accounts` row its internal `login` and the contact-email
    # verification columns migration 012 added (ADR-051, Phase 2 of SSO
    # email-less accounts, design §7 "Backfill op").
    #
    # ## What `login` is
    #
    # The objid of the Customer that belongs to the row. `external_id` is a
    # pure function of it (`Customer#extid`), so once both are set they can
    # never disagree. The value is opaque and internal: it is never emitted
    # by this operation's reports or log lines, only its presence is.
    #
    # ## Decision per row (every gate runs before any write)
    #
    #   external_id present
    #     Customer by external_id      -> login = customer.objid       (:backfilled, branch :by_external_id)
    #     no such Customer             -> :skipped_dangling_external_id (never overwritten here)
    #   external_id blank
    #     exactly one Customer under the stored or the normalized address,
    #     and no OTHER accounts row already links that Customer
    #                                  -> login = objid, external_id = extid (:backfilled, :by_email)
    #     two Customers                -> :skipped_ambiguous_customer
    #     that Customer is linked by another row
    #                                  -> :skipped_customer_linked_elsewhere
    #     no Customer                  -> :skipped_no_customer, unless mint_missing:
    #                                     then login = fresh UUIDv7, external_id =
    #                                     extid(login) (:backfilled, :minted); the
    #                                     N+1 binary creates the Customer under it
    #                                     on the account's next sign-in
    #   another row already holds the chosen login
    #                                  -> :skipped_customer_linked_elsewhere
    #   anything raised                -> :error
    #
    # Two accounts rows are never merged onto one Customer, and an existing
    # `external_id` is never rewritten: a row whose link names a Customer that
    # no longer exists is reported for the operator (`bin/ots customers doctor`).
    #
    # `mint_missing` is off by default because the CURRENT binary, on the next
    # sign-in of such an account, would create a Customer by email and
    # overwrite the minted `external_id` with that Customer's extid, leaving
    # `login` pointing nowhere. Turn it on only once every process reads the
    # Customer by `external_id` and materialises a missing one from `login`
    # (the N+1 binary, design §4.1 K2).
    #
    # ## Verification columns
    #
    # Mailbox verification today lives on the Customer mirror (`verified`,
    # `verified_by`, `verification_hold`) with Rodauth `status_id` as the gate.
    # The copy preserves the current answer, whatever its provenance:
    #
    #   status VERIFIED and customer.verified?  -> email_verified_at = now,
    #                                              email_verified_by = customer.verified_by || 'legacy'
    #   customer.verification_hold present      -> email_verification_hold = that hold
    #   otherwise                               -> all three NULL
    #
    # `email_verified_at` is the backfill time, not the original verification
    # time, which no store recorded; the provenance column carries what is
    # known. A minted row has no Customer to consult, so status VERIFIED alone
    # sets `email_verified_by = 'legacy'`.
    #
    # ## Idempotence and resumability
    #
    # Only rows with `login IS NULL` are candidates, so a second run re-does
    # none of them; refused and errored rows stay candidates and are
    # re-reported on every run until an operator resolves them (`after_id:`
    # skips past them on a limited run). The write is a compare-and-set on
    # `login IS NULL`: a row another process filled between scan and write is
    # reported, not clobbered. Dry run (the default) writes nothing.
    class BackfillAccountLogins
      include Onetime::LoggerMethods

      OUTCOMES = [
        :backfilled,
        :skipped_dangling_external_id,
        :skipped_ambiguous_customer,
        :skipped_customer_linked_elsewhere,
        :skipped_no_customer,
        :error,
      ].freeze

      BRANCHES = [:by_external_id, :by_email, :minted].freeze

      # Provenance recorded when the Customer mirror says verified but carries
      # no verified_by (records that predate the field).
      LEGACY_PROVENANCE = 'legacy'

      # Keyset page size for the accounts scan.
      BATCH_SIZE = 1000

      # @!attribute dry_run [r]
      #   @return [Boolean]
      # @!attribute stats [r]
      #   @return [Hash{Symbol=>Integer}] :scanned plus one count per OUTCOMES
      #     plus one per BRANCHES
      # @!attribute rows [r]
      #   @return [Array<Hash>] one per scanned row:
      #     { account_id:, outcome:, branch:, email:, detail: } with the
      #     address OBSCURED and never the login value
      # @!attribute last_account_id [r]
      #   @return [Integer, nil] id of the last candidate this run processed
      #     (candidates are processed in id order), nil when it processed
      #     none. Pass it back as `after_id:` to resume a limited run.
      Result = Data.define(:dry_run, :stats, :rows, :last_account_id)

      # @param dry_run [Boolean] report only (default). `false` applies.
      # @param limit [Integer, nil] cap on candidate rows processed; nil = all
      # @param after_id [Integer, nil] process only candidates with `id > after_id`
      # @param mint_missing [Boolean] mint a fresh login for rows with no
      #   resolvable Customer (see the class comment for when that is safe)
      # @param db [Sequel::Database, nil] defaults to Auth::Database.connection
      def initialize(dry_run: true, limit: nil, after_id: nil, mint_missing: false, db: nil)
        @dry_run      = dry_run ? true : false
        @limit        = non_negative_integer(limit, 'limit')
        @after_id     = non_negative_integer(after_id, 'after_id')
        @mint_missing = mint_missing ? true : false
        @db           = db || (defined?(Auth::Database) ? Auth::Database.connection : nil)
        raise Onetime::Problem, 'Auth database unavailable (simple auth mode?)' unless @db
        raise Onetime::Problem, 'accounts.login column missing: run migration 012 first' unless login_column?
      end

      # @return [Result]
      def call
        stats                                    = { scanned: 0 }
        OUTCOMES.each { |outcome| stats[outcome] = 0 }
        BRANCHES.each { |branch| stats[branch]   = 0 }
        rows                                     = []
        last_account_id                          = nil

        each_candidate do |row|
          report                   = process_row_safely(row)
          stats[:scanned]         += 1
          stats[report[:outcome]] += 1
          stats[report[:branch]]  += 1 if report[:branch]
          rows << report
          last_account_id          = row[:id]
          log_row(report)
        end

        Auth::Logging.log_operation(
          :backfill_account_logins,
          dry_run: @dry_run,
          mint_missing: @mint_missing,
          last_account_id: last_account_id,
          **stats,
        )

        Result.new(dry_run: @dry_run, stats: stats, rows: rows, last_account_id: last_account_id)
      end

      private

      def non_negative_integer(value, name)
        return nil if value.nil?

        int = Integer(value)
        raise ArgumentError, "#{name}: must be a non-negative Integer (got #{value.inspect})" if int.negative?

        int
      end

      def login_column?
        @db.schema(:accounts).any? { |name, _| name == :login }
      rescue Sequel::Error
        false
      end

      # ------------------------------------------------------------- scan

      # Candidates in id order: rows with no login, past `after_id`, at most
      # `limit`. Keyset-paged on id so each page is bounded. A live run fills
      # `login` on the rows it processes, which removes them from later pages
      # by the predicate rather than by position, so the cursor is the id.
      def each_candidate
        processed = 0
        last_id   = @after_id || 0

        loop do
          batch = accounts
            .select(:id, :email, :external_id, :status_id)
            .where(login: nil)
            .where { id > last_id }
            .order(:id)
            .limit(BATCH_SIZE)
            .all
          break if batch.empty?

          batch.each do |row|
            break if limit_reached?(processed)

            yield row
            processed += 1
          end
          break if limit_reached?(processed)

          last_id = batch.last[:id]
        end
      end

      def limit_reached?(processed)
        @limit ? processed >= @limit : false
      end

      # -------------------------------------------------------------- row

      def process_row_safely(row)
        process_row(row)
      rescue StandardError => ex
        auth_logger.error '[backfill_account_logins] row failed',
          account_id: row[:id],
          exception: ex
        report(row, :error, nil, "#{ex.class}: #{scrub(ex.message, row)}")
      end

      def process_row(row)
        extid = row[:external_id].to_s

        if extid.empty?
          resolve_by_email(row)
        else
          customer = Onetime::Customer.find_by_extid(extid)
          if customer.nil?
            return report(
              row,
              :skipped_dangling_external_id,
              nil,
              'accounts.external_id names a Customer that does not exist; the link is not rewritten ' \
              'here. Run `bin/ots customers doctor` and `bin/ots customers sync-auth-accounts`',
            )
          end

          apply(row, :by_external_id, customer, customer.objid.to_s, nil)
        end
      end

      def resolve_by_email(row)
        customers = email_candidates(row[:email].to_s)

        if customers.size > 1
          return report(
            row,
            :skipped_ambiguous_customer,
            nil,
            "#{customers.size} Customers hold this address under different casings " \
            "(#{customers.map(&:extid).join(', ')}); not merged. Run `bin/ots customers normalize-emails`",
          )
        end

        customer = customers.first
        if customer.nil?
          unless @mint_missing
            return report(
              row,
              :skipped_no_customer,
              nil,
              'no Customer via the stored or the normalized address; re-run with mint_missing once ' \
              'every process materialises Customers from `login`',
            )
          end

          login = SecureRandom.uuid_v7
          return apply(row, :minted, nil, login, derive_extid(login))
        end

        apply(row, :by_email, customer, customer.objid.to_s, customer.extid.to_s)
      end

      # The stored bytes first (migration 007 left mixed-case index entries in
      # place where the lowercase key belonged to another Customer), then the
      # normalized form. Distinct Customers only.
      #
      # @return [Array<Onetime::Customer>]
      def email_candidates(stored)
        return [] if stored.empty?

        found = [stored, OT::Utils.normalize_email(stored)].uniq.filter_map do |candidate|
          customer = Onetime::Customer.find_by_email(candidate)
          customer if customer && !(customer.respond_to?(:anonymous?) && customer.anonymous?)
        end
        found.uniq { |customer| customer.objid.to_s }
      end

      # extid for a login this row is the first holder of. Derivation needs
      # objid provenance, which the objid setter infers from the UUID format,
      # and writes nothing: the extid_lookup entry is populated by save, which
      # the N+1 binary's K2 performs when it creates the Customer.
      def derive_extid(login)
        Onetime::Customer.new(objid: login).extid.to_s
      end

      # The gates that depend on the chosen login, then the write.
      #
      # @param customer [Onetime::Customer, nil] nil only on the :minted branch
      # @param new_external_id [String, nil] nil keeps the row's existing value
      def apply(row, branch, customer, login, new_external_id)
        raise Onetime::Problem, 'empty login' if login.empty?

        holder = accounts.where(login: login).exclude(id: row[:id]).select(:id, :status_id).first
        if holder
          return report(
            row,
            :skipped_customer_linked_elsewhere,
            branch,
            "accounts row #{describe_holder(holder)} already holds this Customer's login; two accounts " \
            "rows name one Customer #{customer&.extid}; not merged",
          )
        end

        if new_external_id && !new_external_id.empty?
          other = accounts.where(external_id: new_external_id).exclude(id: row[:id]).select(:id, :status_id).first
          if other
            return report(
              row,
              :skipped_customer_linked_elsewhere,
              branch,
              "accounts row #{describe_holder(other)} already links Customer #{customer&.extid || new_external_id} " \
              'by external_id; not merged',
            )
          end
        end

        values = verification_values(row, customer)
        return report(row, :backfilled, branch, dry_run_detail(new_external_id, values)) if @dry_run

        update               = values.merge(login: login, updated_at: Sequel::CURRENT_TIMESTAMP)
        update[:external_id] = new_external_id if new_external_id && !new_external_id.empty?

        begin
          rows_updated = accounts.where(id: row[:id], login: nil).update(update)
        rescue Sequel::UniqueConstraintViolation => ex
          return report(
            row,
            :skipped_customer_linked_elsewhere,
            branch,
            "unique violation at write time (#{scrub(ex.message, row)}); another row took this login or " \
            'external_id between scan and write; re-run',
          )
        end

        if rows_updated.zero?
          return report(
            row,
            :error,
            branch,
            "accounts row #{row[:id]} was gone or already had a login when the write ran (nothing written); " \
            'it changed between scan and apply, re-run',
          )
        end

        report(row, :backfilled, branch, written_detail(new_external_id, values))
      end

      # @return [Hash] the three verification columns
      def verification_values(row, customer)
        values          = { email_verified_at: nil, email_verified_by: nil, email_verification_hold: nil }
        status_verified = row[:status_id] == AccountStatuses::VERIFIED

        if customer.nil?
          values[:email_verified_at] = Sequel::CURRENT_TIMESTAMP if status_verified
          values[:email_verified_by] = LEGACY_PROVENANCE if status_verified
          return values
        end

        if status_verified && customer.verified?
          provenance                 = customer.verified_by.to_s
          values[:email_verified_at] = Sequel::CURRENT_TIMESTAMP
          values[:email_verified_by] = provenance.empty? ? LEGACY_PROVENANCE : provenance
        else
          hold                             = customer.verification_hold.to_s
          values[:email_verification_hold] = hold unless hold.empty?
        end

        values
      end

      # ---------------------------------------------------------- lookups

      def accounts
        @db[:accounts]
      end

      def describe_holder(holder)
        status = AccountStatuses::LIVE.include?(holder[:status_id]) ? 'live' : 'closed'
        "#{holder[:id]} (#{status})"
      end

      # ---------------------------------------------------------- reports

      def dry_run_detail(new_external_id, values)
        "would set login#{' and external_id' if new_external_id}, #{describe_verification(values)}"
      end

      def written_detail(new_external_id, values)
        "set login#{' and external_id' if new_external_id}, #{describe_verification(values)}"
      end

      def describe_verification(values)
        if values[:email_verified_at]
          "email_verified_by=#{values[:email_verified_by]}"
        elsif values[:email_verification_hold]
          "email_verification_hold=#{values[:email_verification_hold]}"
        else
          'email unverified'
        end
      end

      def report(row, outcome, branch, detail = nil)
        {
          account_id: row[:id],
          outcome: outcome,
          branch: branch,
          email: OT::Utils.obscure_email(row[:email].to_s),
          detail: detail,
        }
      end

      # Exception messages (Sequel includes the statement) can carry the raw
      # address and the login value; the report must carry neither.
      def scrub(message, row)
        text  = message.to_s
        email = row[:email].to_s
        text  = text.gsub(email, OT::Utils.obscure_email(email)) unless email.empty?
        text.gsub(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, '<login>')
      end

      def log_row(report)
        Auth::Logging.log_operation(
          :backfill_account_login,
          level: report[:outcome] == :error ? :error : :info,
          dry_run: @dry_run,
          account_id: report[:account_id],
          outcome: report[:outcome],
          branch: report[:branch],
          email: report[:email],
          detail: report[:detail],
        )
      end
    end
  end
end
