# lib/onetime/operations/domains/canonical_index_backfill.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — see decision D3 in
# lib/onetime/operations/README.md. Loaded at the call site (CLI), so require
# the audit it builds on explicitly.
require 'onetime/operations/domains/canonical_index_audit'

module Onetime
  module Operations
    module Domains
      # Enter existing custom domain records into
      # CustomDomain.canonical_display_domain_index, from the result of
      # {CanonicalIndexAudit}. The CLI adapter is
      # `bin/ots domains backfill-canonical-index`.
      #
      # ## What it writes
      #
      #   :missing  claim the record's A-label for the record
      #             (HashKey#claim_field, a server-side compare-and-set), then
      #             read the entry back
      #   :stale    release the entry from the record it names, which no longer
      #             exists (HashKey#release_field, ownership-checked), then
      #             claim it for the record as above
      #   unmatched :stale entries (keyed by a name no record has): release,
      #             ownership-checked
      #
      # :ok, :conflict, :collision and :unconvertible rows are never written.
      # A collision group is reported for an operator to resolve: keep one
      # record, remove the others, and run the backfill again.
      #
      # Every write is checked against the state the audit read, so a second
      # run over the same data changes nothing.
      #
      # ## What an apply reports
      #
      # A write that raises is recorded as that action's :error outcome and
      # the remaining actions still run. After the writes the audit runs
      # again; Result#report_audit is that audit, so the counts and
      # Result#attention? describe the index as the apply left it.
      #
      # An apply writes nothing while the audit finds records it could not
      # load (Result#refusal is :unreadable_records): such a record may have a
      # name that a claim would then give to another record.
      #
      # ## Run it with the application stopped
      #
      # The writes take no lock shared with create!, destroy! or
      # CustomDomain::IdentityGuard, so they are only safe while nothing else
      # writes custom domains. See
      # docs/runbooks/custom-domain-canonical-index-backfill.md.
      #
      # ## Audit trail
      #
      # Index housekeeping, like the index repairs in `bin/ots domains doctor`:
      # each write is logged (OT.info) and no ColonelAuditEvent is recorded.
      class CanonicalIndexBackfill
        # @!attribute kind [r] Symbol — :claim (missing entry), :reclaim (stale
        #   entry on the record's own name), :release (stale entry on a name no
        #   record has)
        # @!attribute outcome [r] Symbol — see OUTCOMES
        Action = Data.define(:kind, :canonical, :domain_id, :display_domain, :stale_id, :outcome, :detail)

        # :planned       dry run
        # :claimed       the entry now names the record (after a release, for :reclaim)
        # :already_held  the entry already named the record when the claim ran
        # :released      the stale entry was removed
        # :skipped       the state changed since the audit; nothing was written
        # :refused       another record holds the name; nothing was written
        # :unverified    the claim reported success but the entry read back differently
        # :error         the write raised (detail names the exception); the
        #                actions after it still ran
        OUTCOMES = [:planned, :claimed, :already_held, :released, :skipped, :refused, :unverified, :error].freeze

        CHANGED_OUTCOMES = [:claimed, :released].freeze
        FAILED_OUTCOMES  = [:refused, :unverified, :error].freeze

        # Why an apply wrote nothing.
        #   :unreadable_records  the audit found records it could not load
        REFUSALS = [:unreadable_records].freeze

        # @!attribute audit [r] CanonicalIndexAudit::Result the actions were
        #   planned from, read before any write
        # @!attribute final_audit [r] CanonicalIndexAudit::Result read after the
        #   writes; the same as audit when nothing was applied, nil when that
        #   audit raised
        # @!attribute recheck_error [r] String, nil — why final_audit is nil
        # @!attribute refusal [r] Symbol, nil — see REFUSALS
        Result = Data.define(:dry_run, :audit, :actions, :final_audit, :recheck_error, :refusal) do
          # Actions that wrote (or, in a dry run, would write).
          def changes
            actions.select { |action| (dry_run ? [:planned] : CHANGED_OUTCOMES).include?(action.outcome) }
          end

          def failures
            actions.select { |action| FAILED_OUTCOMES.include?(action.outcome) }
          end

          # Whether the planned writes ran.
          def applied?
            !dry_run && refusal.nil?
          end

          # The audit a report describes: the one after the writes when they
          # ran and it could be read, otherwise the one they were planned from.
          def report_audit
            final_audit || audit
          end

          # Whether an operator has to act: collisions, conflicts, unreadable
          # records, a refused apply, a write that did not land, or, after an
          # apply, entries that are still missing or stale.
          def attention?
            return true if refusal || recheck_error || failures.any? || report_audit.attention?

            applied? && !report_audit.clean?
          end
        end

        # @param dry_run [Boolean] report the plan without writing (default)
        def initialize(dry_run: true)
          @dry_run = dry_run
        end

        # @return [Result]
        def call
          audit   = CanonicalIndexAudit.new.call
          planned = plan(audit)
          return unapplied(audit, planned, nil) if @dry_run
          return unapplied(audit, planned, :unreadable_records) if refuse_unreadable?(audit)

          actions                    = planned.map { |action| apply_recording_errors(action) }
          final_audit, recheck_error = recheck

          Result.new(
            dry_run: false,
            audit: audit,
            actions: actions,
            final_audit: final_audit,
            recheck_error: recheck_error,
            refusal: nil,
          )
        end

        private

        def model
          Onetime::CustomDomain
        end

        def index
          model.canonical_display_domain_index
        end

        def plan(audit)
          claims   = audit.rows_in(:missing).map do |row|
            planned_action(:claim, row.canonical, row.domain_id, row.display_domain, nil)
          end
          reclaims = audit.rows_in(:stale).map do |row|
            planned_action(:reclaim, row.canonical, row.domain_id, row.display_domain, row.holder_id)
          end
          releases = audit.entries_in(:stale).map do |entry|
            planned_action(:release, entry.canonical, nil, nil, entry.holder_id)
          end

          claims + reclaims + releases
        end

        def planned_action(kind, canonical, domain_id, display_domain, stale_id)
          Action.new(
            kind: kind,
            canonical: canonical,
            domain_id: domain_id,
            display_domain: display_domain,
            stale_id: stale_id,
            outcome: :planned,
            detail: nil,
          )
        end

        def unapplied(audit, actions, refusal)
          Result.new(
            dry_run: @dry_run,
            audit: audit,
            actions: actions,
            final_audit: audit,
            recheck_error: nil,
            refusal: refusal,
          )
        end

        def refuse_unreadable?(audit)
          return false if audit.errors.empty?

          OT.le "[Domains::CanonicalIndexBackfill] Not applying: #{audit.errors.size} custom domain " \
                'records could not be loaded; nothing was written'
          true
        end

        # The audit after the writes.
        #
        # @return [Array(CanonicalIndexAudit::Result, nil), Array(nil, String)]
        def recheck
          [CanonicalIndexAudit.new.call, nil]
        rescue StandardError => ex
          OT.le "[Domains::CanonicalIndexBackfill] Audit after the writes failed: #{ex.class}: #{ex.message}"
          [nil, "#{ex.class}: #{ex.message}"]
        end

        # An exception becomes this action's :error outcome, so the actions
        # after it still run and the result lists what each one did.
        def apply_recording_errors(action)
          apply(action)
        rescue StandardError => ex
          OT.le "[Domains::CanonicalIndexBackfill] #{action.kind} of #{action.canonical} raised #{ex.class}: #{ex.message}"
          action.with(outcome: :error, detail: "#{ex.class}: #{ex.message}")
        end

        def apply(action)
          case action.kind
          when :claim then claim(action)
          when :reclaim then reclaim(action)
          when :release then release(action)
          end
        end

        def claim(action)
          return action.with(outcome: :skipped, detail: 'record no longer exists') unless record_exists?(action.domain_id)

          result = index.claim_field(action.canonical, action.domain_id)

          case result
          when :created then verify_claim(action)
          when :owned then action.with(outcome: :already_held)
          else
            OT.le "[Domains::CanonicalIndexBackfill] #{action.canonical} is held by #{result}, " \
                  "not claimed for #{action.domain_id}"
            action.with(outcome: :refused, detail: "entry names #{result}")
          end
        end

        # A claim that reported :created is read back. On a mismatch the claim
        # is released again, ownership-checked, so a value that is not this
        # record's is left alone.
        def verify_claim(action)
          stored = index.get(action.canonical)
          if stored == action.domain_id
            OT.info '[Domains::CanonicalIndexBackfill] Claimed canonical_display_domain_index' \
                    "[#{action.canonical}] for #{action.domain_id} (#{action.display_domain})"
            return action.with(outcome: :claimed)
          end

          index.release_field(action.canonical, action.domain_id)
          OT.le "[Domains::CanonicalIndexBackfill] Claim of #{action.canonical} for #{action.domain_id} " \
                "read back as #{stored.inspect}"
          action.with(outcome: :unverified, detail: "entry read back as #{stored.inspect}")
        end

        def reclaim(action)
          return action.with(outcome: :skipped, detail: "#{action.stale_id} exists again") if record_exists?(action.stale_id)

          released = release_stale(action)
          claimed  = claim(action)
          return claimed unless claimed.outcome == :claimed

          claimed.with(detail: released ? "released #{action.stale_id}" : nil)
        end

        def release(action)
          return action.with(outcome: :skipped, detail: "#{action.stale_id} exists again") if record_exists?(action.stale_id)
          return action.with(outcome: :released) if release_stale(action)

          action.with(outcome: :skipped, detail: 'entry changed since the audit')
        end

        # @return [Boolean] whether the entry was removed
        def release_stale(action)
          released = index.release_field(action.canonical, action.stale_id).to_i == 1
          if released
            OT.info '[Domains::CanonicalIndexBackfill] Released canonical_display_domain_index' \
                    "[#{action.canonical}] from #{action.stale_id}, which no longer exists"
          end
          released
        end

        def record_exists?(identifier)
          return false if identifier.to_s.empty?

          model.dbclient.exists?(model.dbkey(identifier))
        end
      end
    end
  end
end
