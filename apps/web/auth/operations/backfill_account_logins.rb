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
    #   the chosen Customer holds a different address than the row
    #   (compared case-insensitively, as `customers doctor` does)
    #                                  -> :skipped_email_mismatch
    #   the row is Verified and the Customer verified with a verified_by
    #   outside Onetime::Customer::VERIFIED_BY_VALUES
    #                                  -> :skipped_unknown_verified_by
    #   another row already holds the chosen login
    #                                  -> :skipped_customer_linked_elsewhere
    #   anything raised                -> :error
    #
    # Two accounts rows are never merged onto one Customer, and an existing
    # `external_id` is never rewritten: a row whose link names a Customer that
    # no longer exists is reported for the operator, with what settles it
    # (#dangling_detail). `customers doctor` and `customers sync-auth-accounts`
    # start from Customer records, so neither reaches such a row by its link.
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
    # `email_verified_at` therefore agrees with `customer.verified?`, and
    # `email_verified_by` carries the provenance unchanged. Whether that
    # provenance is mailbox proof is decided where the Customer decides it,
    # Onetime::Customer::MAILBOX_VERIFIED_BY (#4754): an 'sso', 'legacy' or
    # 'stripe_payment' row is verified but has no mailbox proof, exactly as
    # its Customer is. A tag written here is always one of
    # Onetime::Customer::VERIFIED_BY_VALUES (#4892); a Customer carrying any
    # other is skipped (:skipped_unknown_verified_by) for an operator to
    # re-stamp.
    #
    # `email_verified_at` is the backfill time, not the original verification
    # time, which no store recorded; the provenance column carries what is
    # known. A minted row has no Customer to consult, so all three stay NULL:
    # status VERIFIED is not mailbox evidence (an SSO account opens Verified
    # even when its IdP reported the address unverified).
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
        :skipped_email_mismatch,
        :skipped_unknown_verified_by,
        :skipped_no_customer,
        :error,
      ].freeze

      BRANCHES = [:by_external_id, :by_email, :minted].freeze

      # Provenance recorded when the Customer mirror says verified but carries
      # no verified_by (records that predate the field).
      LEGACY_PROVENANCE = 'legacy'

      # Keyset page size for the accounts scan.
      BATCH_SIZE = 1000

      # Backtrace lines logged for a row that raised. A backtrace holds code
      # locations only, never the values the exception message can carry.
      LOGGED_BACKTRACE_LINES = 5

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

      # The exception object is never logged: its message can carry the
      # statement's values (a Sequel error names the duplicate key), which
      # is the raw address or the login. The log and the report get the
      # scrubbed message, and the log a short backtrace.
      def process_row_safely(row)
        process_row(row)
      rescue StandardError => ex
        detail = "#{ex.class}: #{scrub(ex.message, row)}"
        auth_logger.error '[backfill_account_logins] row failed',
          account_id: row[:id],
          error: detail,
          backtrace: Array(ex.backtrace).first(LOGGED_BACKTRACE_LINES)
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

      # What settles a row whose external_id names no Customer. Read-only:
      # it looks up who holds the row's address, which decides the case.
      #
      #   closed row                  prune-closed-accounts deletes it
      #   one Customer holds the      the account's next sign-in re-links the
      #   address, no row links it    row to it (SyncSession), as does
      #                               sync-auth-accounts, which links a live
      #                               row by address (exact match; citext on
      #                               PostgreSQL)
      #   ...but another row links it a manual decision; never merged
      #   no Customer holds it        the next sign-in recreates the Customer
      #                               and re-links the row
      #   several Customers hold it   normalize-emails first
      def dangling_detail(row)
        lead = 'accounts.external_id names a Customer that does not exist, and this command never ' \
               'rewrites it. '
        unless AccountStatuses.live?(row[:status_id])
          return lead + 'The row is closed: `bin/ots customers prune-closed-accounts` deletes closed ' \
                        'rows (dry run first)'
        end

        holders = email_candidates(row[:email].to_s)
        return lead + dangling_without_holder if holders.empty?

        if holders.size > 1
          return lead + "#{holders.size} Customers hold this row's address under different casings " \
                        "(#{holders.map(&:extid).join(', ')}): run `bin/ots customers normalize-emails` " \
                        'first, then re-run'
        end

        holder = holders.first
        other  = accounts.where(external_id: holder.extid.to_s).exclude(id: row[:id]).select(:id, :status_id).first
        if other
          return lead + "Customer #{holder.extid} holds this row's address, but accounts row " \
                        "#{describe_holder(other)} links it: decide which account keeps the Customer " \
                        '(never merged), then re-run'
        end

        lead + "Customer #{holder.extid} holds this row's address and no row links it. The account's " \
               'next sign-in re-links the row to it. To do it now, `bin/ots customers sync-auth-accounts` ' \
               "links a live row to the Customer whose address it holds (exactly; any case on PostgreSQL), " \
               'and also creates rows for Customers that have none: read its dry run, then pass --run. ' \
               'Then re-run'
      end

      def dangling_without_holder
        "No Customer holds this row's address either. The account's next sign-in recreates its " \
          'Customer and re-links the row; until then there is no Customer to take a login from. Then re-run'
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

      # The gates that depend on the chosen Customer and login, then the
      # write.
      #
      # @param customer [Onetime::Customer, nil] nil only on the :minted branch
      # @param new_external_id [String, nil] nil keeps the row's existing value
      def apply(row, branch, customer, login, new_external_id)
        raise Onetime::Problem, 'empty login' if login.empty?

        if customer && !same_address?(row, customer)
          return report(row, :skipped_email_mismatch, branch, email_mismatch_detail(branch, customer))
        end

        unknown = unknown_provenance(row, customer)
        if unknown
          return report(
            row,
            :skipped_unknown_verified_by,
            branch,
            "Customer #{customer.extid} is verified with verified_by #{unknown.inspect}, which is not one of " \
            "Onetime::Customer::VERIFIED_BY_VALUES; not copied. Confirm the address and re-stamp it " \
            "(`bin/ots customers verify #{customer.extid}`), then re-run",
          )
        end

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

      # A row with no Customer (the :minted branch) gets all three NULL.
      # Rodauth status 2 alone is not mailbox evidence (ADR-051 decision 1):
      # rodauth-omniauth opens every SSO account Verified whatever the IdP
      # said about the address, and the hold that records an unverified
      # claim lives only on the Customer this row does not have.
      #
      # @return [Hash] the three verification columns
      def verification_values(row, customer)
        values = { email_verified_at: nil, email_verified_by: nil, email_verification_hold: nil }
        return values if customer.nil?

        if row[:status_id] == AccountStatuses::VERIFIED && customer.verified?
          provenance                 = customer.verified_by.to_s
          values[:email_verified_at] = Sequel::CURRENT_TIMESTAMP
          values[:email_verified_by] = provenance.empty? ? LEGACY_PROVENANCE : provenance
        else
          hold                             = customer.verification_hold.to_s
          values[:email_verification_hold] = hold unless hold.empty?
        end

        values
      end

      # The verified_by this row would copy when it is not a known
      # provenance tag, else nil. Only a tag that would be written counts:
      # an Unverified row, or an unverified Customer, copies none.
      #
      # @return [String, nil]
      def unknown_provenance(row, customer)
        return if customer.nil?
        return unless row[:status_id] == AccountStatuses::VERIFIED && customer.verified?

        provenance = customer.verified_by.to_s
        return if provenance.empty? || Onetime::Customer::VERIFIED_BY_VALUES.include?(provenance)

        provenance
      end

      # Whether the row and the Customer name one address. The Customer's
      # verification is proof for the Customer's address, so it is copied
      # only when the row holds that address too. Case-insensitive, the rule
      # `customers doctor` applies (:auth_email_drift): accounts.email is
      # citext on PostgreSQL, and a case-only difference is the same mailbox.
      # Not case-FOLDED: folding maps `ß` to `ss`, which names another
      # mailbox.
      def same_address?(row, customer)
        row[:email].to_s.downcase == customer.email.to_s.downcase
      end

      def email_mismatch_detail(branch, customer)
        if branch == :by_external_id
          "Customer #{customer.extid} holds a different address than this row (`bin/ots customers doctor " \
            "#{customer.extid}` reports it as auth_email_drift); its verification is not this address's. " \
            'Settle the address first (`customers doctor --repair` writes the Customer address into the row), ' \
            'then re-run'
        else
          "the only Customer found for this row's address, #{customer.extid}, holds an address that is not " \
            "the row's (they match only when case-folded); not linked. Decide by hand which Customer owns " \
            'the account, then re-run'
        end
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
      # address and the login value; the report and the log must carry
      # neither. The address is masked as stored and as normalized, since a
      # lookup by the normalized form can raise with that form in the text.
      def scrub(message, row)
        text  = message.to_s
        email = row[:email].to_s
        unless email.empty?
          [email, OT::Utils.normalize_email(email)].uniq.each do |form|
            text = text.gsub(form, OT::Utils.obscure_email(form))
          end
        end
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
