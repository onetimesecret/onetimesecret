# apps/web/auth/operations/backfill_account_logins.rb
#
# frozen_string_literal: true

# Loaded from the CLI (outside the auth app's autoloader), so every
# dependency is required explicitly.
require 'securerandom'
require 'auth/account_statuses'
require 'auth/account_email_verification'
require 'auth/database'
require 'auth/lib/logging'

module Auth
  module Operations
    # Give every `accounts` row its internal `login` and the contact-email
    # verification columns migration 015 added (ADR-051, Phase 2 of SSO
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
    #     no such Customer             -> :skipped_dangling_external_id (never overwritten here;
    #                                     the report says whether a Customer holds the
    #                                     row's address, which decides the repair, see
    #                                     #dangling_detail)
    #   external_id blank
    #     the row is CLOSED            -> :skipped_closed_row, unless mint_missing:
    #                                     then minted as below. Never linked by
    #                                     address (#closed_row)
    #     the address is fold-unstable -> :skipped_fold_unstable (#fold_unstable_row)
    #     the email index names only Customers that hold another address
    #                                  -> :skipped_index_mismatch (#index_mismatch_row)
    #     exactly one Customer under the stored or the normalized address
    #     that holds the row's address, and no OTHER accounts row already
    #     links that Customer
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
    #   the row changed between scan and write
    #                                  -> :skipped_row_changed (re-read on the next run)
    #   anything raised                -> :error
    #
    # Two accounts rows are never merged onto one Customer, and an existing
    # `external_id` is never rewritten: a row whose link names a Customer that
    # no longer exists is reported for the operator with the repair that fits
    # what the report found.
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
    # `email_verified_at` records that mailbox control was established for the
    # row's CURRENT `email` (migration 015). The only record of that today is
    # the Customer mirror (`verified`, `verified_by`, `verification_hold`),
    # and not every `verified` stamp there is mailbox proof:
    # `Onetime::Customer::MAILBOX_VERIFIED_BY` lists the provenances that are
    # (a followed link, an invite token, an operator), and
    # `Customer#mailbox_verified?` reads it. The copy is conservative:
    #
    #   Rodauth status VERIFIED, Customer#mailbox_verified?, and the Customer's
    #   address is the row's address (#same_address?)
    #                                           -> email_verified_at = now,
    #                                              email_verified_by = customer.verified_by
    #   same address, not mailbox-verified, and
    #   customer.verification_hold present      -> email_verification_hold = that hold
    #   otherwise                               -> all three NULL
    #
    # "Otherwise" covers an unverified Customer; one verified by an IdP claim
    # ('sso'), a payment, autoverify or a pre-provenance 'legacy' stamp, none
    # of which proves the mailbox (ADR-051 keeps mailbox proof apart from an
    # IdP assertion); a Customer that holds a different address, whose proof
    # says nothing about this row's; and a row with no Customer at all (the
    # :minted branch), where Rodauth status alone is not evidence. A row left
    # NULL here loses nothing: the Customer mirror keeps its own answer and is
    # what every reader uses until the N+1 binary makes SQL the writer.
    # Every later verification change writes the columns too
    # (SetCustomerVerification, the after_verify_account hook, the invite
    # signup, ChangeEmail), through the same mapping
    # (Auth::AccountEmailVerification), so this copy stays current after the
    # run.
    #
    # `email_verified_at` is the backfill time, not the original verification
    # time, which no store recorded; the provenance column carries what is
    # known.
    #
    # ## Idempotence and resumability
    #
    # Only rows with `login IS NULL` are candidates, so a second run re-does
    # none of them; refused and errored rows stay candidates and are
    # re-reported on every run until an operator resolves them (`after_id:`
    # skips past them on a limited run). The write is a compare-and-set on the
    # row AS SCANNED: `login IS NULL` plus the scanned external_id, email and
    # status_id (#unchanged_scope). A row another process changed in between
    # (sync-auth-accounts re-linking its external_id, an email change, a
    # closure) is reported as :skipped_row_changed, not clobbered, and is
    # re-read on the next run. Dry run (the default) writes nothing.
    class BackfillAccountLogins
      include Onetime::LoggerMethods

      OUTCOMES = [
        :backfilled,
        :skipped_dangling_external_id,
        :skipped_ambiguous_customer,
        :skipped_customer_linked_elsewhere,
        :skipped_no_customer,
        :skipped_closed_row,
        :skipped_fold_unstable,
        :skipped_index_mismatch,
        :skipped_row_changed,
        :error,
      ].freeze

      BRANCHES = [:by_external_id, :by_email, :minted].freeze

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
        raise Onetime::Problem, 'accounts.login column missing: run migration 015 first' unless login_column?
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

      # The exception object itself never reaches a logger: a database error
      # carries the statement, and the statement carries the address and the
      # login value. Only the scrubbed detail is logged and reported.
      def process_row_safely(row)
        process_row(row)
      rescue StandardError => ex
        detail = "#{ex.class}: #{scrub(ex.message, row)}"
        auth_logger.error '[backfill_account_logins] row failed', account_id: row[:id], error: detail
        report(row, :error, nil, detail)
      end

      def process_row(row)
        extid = row[:external_id].to_s

        if extid.empty?
          resolve_by_email(row)
        else
          customer = Onetime::Customer.find_by_extid(extid)
          return report(row, :skipped_dangling_external_id, nil, dangling_detail(row)) if customer.nil?

          apply(row, :by_external_id, customer, customer.objid.to_s, nil)
        end
      end

      # The repair for a dangling link depends on a fact `bin/ots customers
      # doctor` cannot see (it walks Customers, and this row's is gone):
      # whether some Customer holds the row's address. With one, the current
      # binary re-links the row to it on the account's next sign-in
      # (SyncSession link-on-login) and `sync-auth-accounts` does the same for
      # a live row now. With none the row is orphaned; `customers diagnose`
      # resolves a numeric account id without a Customer and names it so, and
      # the next sign-in recreates a Customer under the address
      # (SyncSession#recreate_customer). Either way the row stays a candidate
      # and the re-run links it.
      def dangling_detail(row)
        holders = email_candidates(row[:email].to_s)
        base    = 'accounts.external_id names a Customer that does not exist; the link is not rewritten here. '

        if holders.empty?
          base +
            "No Customer holds this address either, so the row is orphaned: `bin/ots customers diagnose #{row[:id]}` " \
            'reports it as orphaned_auth_account. The account\'s next sign-in recreates a Customer under the address ' \
            'and re-links the row; otherwise decide by hand whether the account stays. Re-run afterwards'
        else
          base +
            "Customer #{holders.map(&:extid).join(', ')} holds this address: `bin/ots customers sync-auth-accounts " \
            '--run` re-links a live row to it (so does the account\'s next sign-in). Re-run afterwards'
        end
      end

      def resolve_by_email(row)
        return closed_row(row) unless AccountStatuses.live?(row[:status_id])
        return fold_unstable_row(row) unless fold_stable_address?(row[:email])

        indexed   = email_candidates(row[:email].to_s)
        customers = indexed.select { |customer| same_address?(row, customer) }
        return index_mismatch_row(row, indexed) if customers.empty? && indexed.any?

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

      # A closed row has no claim on the Customer at its address. The unique
      # index on accounts.email is partial (LIVE rows only, AccountStatuses),
      # so a closed row can share a live row's address, and it normally has
      # the lower id: linked by address, it would take the live account's
      # Customer and leave the live row refused as linked elsewhere. A closed
      # row cannot sign in, so a fresh login (mint_missing) is all it needs.
      def closed_row(row)
        if @mint_missing
          login = SecureRandom.uuid_v7
          return apply(row, :minted, nil, login, derive_extid(login))
        end

        report(
          row,
          :skipped_closed_row,
          nil,
          'closed row with no external_id: never linked to a Customer by address (a live row may hold it); ' \
          're-run with mint_missing to give it a fresh login',
        )
      end

      # Case folding rewrites a few non-ASCII addresses into different ones
      # (ß -> ss), so the folded form of such an address is an address nobody
      # asserted, and the Customer under it may be someone else.
      # NormalizeAccountEmails refuses the same rows (OT::Utils.fold_stable_email?).
      def fold_unstable_row(row)
        report(
          row,
          :skipped_fold_unstable,
          nil,
          'case folding would rewrite the address (for example ß -> ss), so it cannot be matched to a ' \
          'Customer by its folded form; left for the operator',
        )
      end

      # The email index names a Customer under this address, but that
      # Customer holds another one: the index entry is stale
      # (`customers doctor --all` reports it as email_index_mismatch and
      # `--repair` re-points it). Linking by the entry would give this row an
      # unrelated Customer's login for good, since a linked row is never a
      # candidate again. Not minted either: once the index is repaired the
      # address may resolve to its real holder. NormalizeAccountEmails refuses
      # the same case.
      def index_mismatch_row(row, indexed)
        report(
          row,
          :skipped_index_mismatch,
          nil,
          "the email index maps this address to Customer #{indexed.map(&:extid).join(', ')}, which holds " \
          'another address; not linked. Run `bin/ots customers doctor --all --repair` (email_index_mismatch), ' \
          'then re-run',
        )
      end

      # @param value [String, nil] an address as read from SQL or Redis
      def fold_stable_address?(value)
        OT::Utils.fold_stable_email?(OT::Utils.canonical_email(sql_text(value)))
      end

      # The stored bytes first (migration 007 left mixed-case index entries in
      # place where the lowercase key belonged to another Customer), then the
      # normalized form, unless folding would rewrite the address into a
      # different one (#fold_unstable_row). Distinct Customers only.
      #
      # @return [Array<Onetime::Customer>]
      def email_candidates(stored)
        stored = sql_text(stored)
        return [] if stored.empty?

        forms = [stored]
        forms << OT::Utils.normalize_email(stored) if fold_stable_address?(stored)

        found = forms.uniq.filter_map do |candidate|
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
          rows_updated = unchanged_scope(row).update(update)
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
            :skipped_row_changed,
            branch,
            'the row changed between scan and write (its login, external_id, email or status is not what the ' \
            'scan read); nothing written; it is re-read on the next run',
          )
        end

        report(row, :backfilled, branch, written_detail(new_external_id, values))
      end

      # The compare-and-set predicate: the row exactly as the scan read it.
      # `login IS NULL` alone is not enough. The login chosen above was
      # derived from the scanned external_id (or from the scanned address),
      # so a row whose external_id was re-linked in between (sync-auth-accounts,
      # link-on-login) would otherwise end up with a login naming one
      # Customer and an external_id naming another. Sequel renders a nil
      # value as `IS NULL`, so an unlinked row compares too. On PostgreSQL
      # accounts.email is citext, so a case-only rewrite still matches; it
      # names the same address.
      def unchanged_scope(row)
        accounts.where(
          id: row[:id],
          login: nil,
          external_id: row[:external_id],
          email: row[:email],
          status_id: row[:status_id],
        )
      end

      # The mapping every writer shares (Auth::AccountEmailVerification),
      # with the row's Rodauth status as one more condition for proof.
      #
      # @return [Hash] the three verification columns (see the class comment)
      def verification_values(row, customer)
        return Auth::AccountEmailVerification::CLEARED if customer.nil?

        Auth::AccountEmailVerification.values_for_row(
          sql_text(row[:email]),
          customer.email,
          verified: row[:status_id] == AccountStatuses::VERIFIED && customer.verified?,
          verified_by: customer.verified_by,
          hold: customer.verification_hold,
        )
      end

      # Does the Customer hold the row's address? Both sides go through the
      # normalization Customer.create! keys the email index with
      # (OT::Utils.normalize_email: trimmed, NFC, case-folded), which is also
      # how #email_candidates finds a Customer for a row, except that two
      # addresses only folding makes equal (`straße`, `strasse`) are not the
      # same (OT::Utils.same_mailbox?). Proof the Customer carries for another
      # mailbox says nothing about this row's.
      def same_address?(row, customer)
        OT::Utils.same_mailbox?(sql_text(row[:email]), customer.email)
      end

      # ---------------------------------------------------------- lookups

      def accounts
        @db[:accounts]
      end

      # A string column read through a connection whose client_encoding is
      # not UTF8 (a SQL_ASCII cluster) arrives tagged BINARY, and Unicode
      # normalization and UTF-8 pattern matching both raise on that tag.
      # Re-tag before either (OT::Utils.utf8_safe, the project's helper for
      # "whatever the datastore held"); the compare-and-set and the report
      # keep using the bytes as read.
      def sql_text(value)
        OT::Utils.utf8_safe(value.to_s)
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
        text  = OT::Utils.utf8_safe(message.to_s)
        email = sql_text(row[:email])
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
