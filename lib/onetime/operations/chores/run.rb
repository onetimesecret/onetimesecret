# lib/onetime/operations/chores/run.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/audit_reason'
require 'onetime/operations/audit_attempt'
require 'onetime/jobs/job_run'
require 'onetime/jobs/scheduled/housekeeping_job'
require 'onetime/jobs/scheduled/maintenance/entitlement_materialize_job'
require 'onetime/operations/chores/catalog'
require 'onetime/operations/chores/budget'
# The entitlement job resolves both at run time and requires neither (its file
# stays side-effect free for Jobs::Registry). Without Pull loaded, its pull
# gate would rescue the NameError and every console run would abort.
require_relative '../../../../apps/web/billing/operations/catalog/pull'
require_relative '../../../../apps/web/billing/operations/materialize_plans'

module Onetime
  module Operations
    module Chores
      # Run ONE allowlisted chore on demand (#4343) — the operation behind
      # `POST /api/colonel/chores/:chore/run`.
      #
      # ## Synchronous and bounded
      #
      # No worker runs chores, so a console run executes inside the HTTP
      # request, which Caddy abandons after 15 s (`read_timeout`). Two bounds
      # keep it inside that:
      #
      # - `limit` records (default {DEFAULT_LIMIT}, at most {MAX_LIMIT};
      #   larger values are clamped). `capped` in the result means the run
      #   stopped at the limit.
      # - a wall-clock {Budget} of {BUDGET_SECONDS}, checked between records.
      #   `budget_exhausted` means it stopped because time ran out. The record
      #   loop always gets at least {MIN_LOOP_SECONDS} from its first check,
      #   so the entitlement run's catalog pull, which comes first and cannot
      #   be interrupted, cannot leave the materialize with no time at all.
      #
      # Either way the counts in the report cover only the records reached;
      # the full-fleet run is the CLI command in the catalog entry.
      #
      # What the budget cannot interrupt: one record's chore once started
      # (ensure_member_through_models walks every member of an org), and the
      # entitlement run's catalog pull, which is Stripe API calls with a 30 s
      # request timeout and retries (Billing::StripeClient::REQUEST_TIMEOUT,
      # Catalog::StripeRetry). A slow Stripe can push the entitlement run past
      # Caddy's timeout; the run still completes server-side and is audited,
      # but the console sees a gateway error.
      #
      # ## Dry run
      #
      # Housekeeping chores have no dry-run mode: each chore body writes when
      # it finds work (docs/development/data-migrations.md). A dry run of a
      # housekeeping chore therefore NEVER executes it. It counts the records a
      # run would scan (one ZCARD) and reports `dry_run_supported: false`, so
      # the preview cannot be read as "the chore found nothing to change".
      #
      # The entitlement run's dry run is real: MaterializePlans with
      # `dry_run: true` evaluates each org without writing. It reads the
      # CACHED plan catalog and deliberately skips the catalog pull, because a
      # preview must create no keys (try/unit/colonel/dry_run_side_effects_try.rb).
      #
      # ## Live run
      #
      # Housekeeping: HousekeepingJob.perform with the one chore. Entitlement:
      # EntitlementMaterializeJob.perform, which pulls the catalog first and
      # refuses to materialize unless the pull verified it (#4203) — the same
      # gate as the nightly job. A live run writes a JobRun record under
      # `chore.<id>` (preview runs write none).
      #
      # ## Audit (exactly one event per call)
      #
      # - Live run that changed records: `chore.run`, `result: :success`,
      #   FAIL-CLOSED (#4333) — chores rewrite customer data, and the event is
      #   the only record that this operator triggered it.
      # - Live run that changed nothing (nothing modified, nothing failed; for
      #   the entitlement run, also no plans synced into the cache; or the
      #   entitlement run skipped for want of a Stripe key): a no-change
      #   attempt on the operator trail (#4337).
      # - Entitlement run aborted by its pull gate: `result: :failure`,
      #   `outcome: 'aborted'`, not fail-closed (nothing was materialized).
      # - Dry run: ONE observation (`result: 'preview'`), never the operator
      #   trail.
      # - Raise: AuditedFailure records `result: :failure` and re-raises.
      #
      # Details carry counts and reason codes only, never record ids. An
      # operator-supplied `reason:` (#4338) is added to every detail.
      class Run
        include ::Onetime::AuditedFailure
        include ::Onetime::AuditReason
        include ::Onetime::Operations::AuditAttempt

        AUDIT_VERB = 'chore.run'

        DEFAULT_LIMIT    = 100
        MAX_LIMIT        = 1_000
        BUDGET_SECONDS   = 8
        # Floor for the record loop, from its first budget check; see Budget.
        MIN_LOOP_SECONDS = 3

        # Outcome of an entitlement run its catalog-pull gate refused.
        ABORTED = 'aborted'

        # Report keys copied into audit details when their value is a count.
        SUMMARY_KEYS = %w[
          would_scan total scanned modified errors would_materialize
          plans_synced succeeded failed skipped_no_plan
        ].freeze

        # Report keys copied into audit details as reason codes.
        CODE_KEYS = %w[skipped aborted].freeze

        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @chore },
          detail: -> { { dry_run: @dry_run, limit: @limit } }

        # @!attribute status [r] Symbol :success / :dry_run / :skipped / :aborted
        # @!attribute capped [r] Boolean stopped at the record limit
        # @!attribute budget_exhausted [r] Boolean stopped at the time budget
        # @!attribute duration_ms [r] Integer wall-clock time of the call
        # @!attribute report [r] Hash string-keyed counts (see the class doc)
        Result = Data.define(
          :status,
          :chore,
          :kind,
          :dry_run,
          :limit,
          :capped,
          :budget_exhausted,
          :duration_ms,
          :report,
        )

        # @param chore [String] a {Catalog} id
        # @param actor [String] acting admin's PUBLIC identity (extid)
        # @param dry_run [Boolean]
        # @param limit [Integer, nil] clamped to 1..{MAX_LIMIT}; nil is
        #   {DEFAULT_LIMIT}
        # @param reason [String, nil] OPTIONAL operator-supplied why (#4338)
        # @param budget [#exhausted?, #elapsed_ms, nil] defaults to a fresh
        #   {Budget} of {BUDGET_SECONDS} when the call starts
        # @raise [ArgumentError] when `chore` is not runnable (unknown,
        #   excluded, or not listed right now)
        def initialize(chore:, actor:, dry_run: false, limit: DEFAULT_LIMIT, reason: nil, budget: nil)
          @entry = Catalog.find(chore)
          raise ArgumentError, "unknown chore #{chore.to_s.inspect}" unless @entry

          @chore            = @entry.id
          @actor            = actor
          @dry_run          = dry_run ? true : false
          @limit            = (limit || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
          @reason           = normalize_reason(reason)
          @budget           = budget
          @capped           = false
          @budget_exhausted = false
        end

        # @return [Result]
        def call
          @budget ||= Budget.new(BUDGET_SECONDS, min_loop_seconds: MIN_LOOP_SECONDS)
          @dry_run ? preview : run_live
        end

        private

        # The #4337 envelope's target hook: the chore id.
        def audit_target = @chore

        # ---- Dry run ------------------------------------------------------

        def preview
          report = @entry.housekeeping? ? housekeeping_preview : entitlement_preview
          record_preview_observation(with_reason({ limit: @limit }.merge(summary(report))))
          result(:dry_run, report)
        end

        # Never runs the chore: housekeeping chores write when they find work.
        def housekeeping_preview
          total = Catalog.model_class(@entry).instances.size
          { 'would_scan' => [total, @limit].min, 'total' => total, 'dry_run_supported' => false }
        end

        # No catalog pull: a preview must not write the plan cache.
        def entitlement_preview
          outcome           = ::Billing::Operations::MaterializePlans.call(
            include_memberships: true,
            dry_run: true,
            limit: @limit,
            budget: @budget,
          )
          @capped           = outcome.scanned >= @limit
          @budget_exhausted = outcome.budget_exhausted
          {
            'scanned' => outcome.scanned,
            'would_materialize' => outcome.succeeded,
            'skipped_no_plan' => outcome.skipped_no_plan,
            'plan_not_found' => outcome.failed,
            'catalog_pulled' => false,
          }
        end

        # ---- Live run -----------------------------------------------------

        def run_live
          ::Onetime::Jobs::JobRun.started(@entry.run_id)
          status, report = @entry.housekeeping? ? run_housekeeping : run_entitlements
          record_run(status, report)
          finish_run(status, report)
          result(status, report)
        rescue StandardError => ex
          ::Onetime::Jobs::JobRun.finished(
            @entry.run_id,
            status: 'error',
            duration_ms: @budget.elapsed_ms,
            error: "#{ex.class}: #{ex.message}",
          )
          raise
        end

        def run_housekeeping
          stats             = ::Onetime::Jobs::Scheduled::HousekeepingJob.perform(
            Catalog.model_class(@entry),
            @entry.chore,
            limit: @limit,
            budget: @budget,
          )
          counts            = stats[:chores].fetch(@entry.chore.to_sym)
          @capped           = stats[:scanned] >= @limit
          @budget_exhausted = stats[:budget_exhausted] == true
          report            = {
            'model' => stats[:model],
            'scanned' => stats[:scanned],
            'modified' => counts[:modified],
            'errors' => counts[:errors],
          }
          [:success, report]
        end

        # The job pulls the catalog, gates on it, then materializes.
        def run_entitlements
          job_report        = ::Onetime::Jobs::Scheduled::Maintenance::EntitlementMaterializeJob.perform(
            {},
            limit: @limit,
            budget: @budget,
          )
          @capped           = job_report[:scanned].to_i >= @limit
          @budget_exhausted = job_report[:budget_exhausted] == true
          status            = if job_report[:skipped]
                                :skipped
                              elsif job_report[:aborted]
                                :aborted
                              else
                                :success
                              end
          [status, stringify(job_report)]
        end

        def record_run(status, report)
          detail = with_reason(run_detail(status, report))

          if status == :aborted
            record_aborted(detail)
          elsif no_change?(status, report)
            record_no_change_attempt(detail)
          else
            ::Onetime::ColonelAuditEvent.record(
              actor: audit_actor,
              verb: audit_verb,
              target: audit_target,
              result: :success,
              detail: detail,
              fail_closed: true,
            )
          end
        end

        # The pull gate refused, so nothing was materialized: an attempt that
        # failed, not an applied change, and not fail-closed.
        def record_aborted(detail)
          ::Onetime::ColonelAuditEvent.record(
            actor: audit_actor,
            verb: audit_verb,
            target: audit_target,
            result: :failure,
            detail: detail.merge(outcome: ABORTED),
          )
        end

        # Nothing modified and nothing failed. For the entitlement run the
        # catalog pull is a write too: a pull that synced plans rewrote the
        # plan cache even when the materialize reached no org. A skipped
        # entitlement run (no Stripe key) moved nothing.
        def no_change?(status, report)
          return true if status == :skipped

          if @entry.housekeeping?
            report['modified'].to_i.zero? && report['errors'].to_i.zero?
          else
            report['succeeded'].to_i.zero? && report['failed'].to_i.zero? && report['plans_synced'].to_i.zero?
          end
        end

        def run_detail(status, report)
          {
            dry_run: false,
            limit: @limit,
            capped: @capped,
            budget_exhausted: @budget_exhausted,
            status: status.to_s,
          }.merge(summary(report))
        end

        # JobRun vocabulary (D1): an aborted run is an error with the reason.
        def finish_run(status, report)
          run_status, error = case status
                              when :success then ['success', nil]
                              when :skipped then ['skipped', nil]
                              else ['error', "#{ABORTED}: #{report[ABORTED]}"]
                              end
          ::Onetime::Jobs::JobRun.finished(
            @entry.run_id,
            status: run_status,
            duration_ms: @budget.elapsed_ms,
            error: error,
          )
        end

        # ---- Shared -------------------------------------------------------

        # Counts and reason codes only: never record ids.
        def summary(report)
          counts = report.slice(*SUMMARY_KEYS).select { |_key, value| value.is_a?(Integer) }
          codes  = report.slice(*CODE_KEYS).select { |_key, value| value.is_a?(String) }
          counts.merge(codes).transform_keys(&:to_sym)
        end

        def stringify(value)
          case value
          when Hash then value.to_h { |key, item| [key.to_s, stringify(item)] }
          when Array then value.map { |item| stringify(item) }
          else value
          end
        end

        def result(status, report)
          Result.new(
            status: status,
            chore: @chore,
            kind: @entry.kind,
            dry_run: @dry_run,
            limit: @limit,
            capped: @capped,
            budget_exhausted: @budget_exhausted,
            duration_ms: @budget.elapsed_ms,
            report: report,
          )
        end
      end
    end
  end
end
