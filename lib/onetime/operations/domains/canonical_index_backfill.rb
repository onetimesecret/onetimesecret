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
        OUTCOMES = [:planned, :claimed, :already_held, :released, :skipped, :refused, :unverified].freeze

        CHANGED_OUTCOMES = [:claimed, :released].freeze
        FAILED_OUTCOMES  = [:refused, :unverified].freeze

        Result = Data.define(:dry_run, :audit, :actions) do
          # Actions that wrote (or, in a dry run, would write).
          def changes
            actions.select { |action| (dry_run ? [:planned] : CHANGED_OUTCOMES).include?(action.outcome) }
          end

          def failures
            actions.select { |action| FAILED_OUTCOMES.include?(action.outcome) }
          end

          # Whether an operator has to act: collisions, conflicts, unreadable
          # records, or a write that did not land.
          def attention?
            audit.attention? || failures.any?
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
          actions = @dry_run ? planned : planned.map { |action| apply(action) }

          Result.new(dry_run: @dry_run, audit: audit, actions: actions)
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
