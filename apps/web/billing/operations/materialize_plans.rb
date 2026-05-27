# apps/web/billing/operations/materialize_plans.rb
#
# frozen_string_literal: true

module Billing
  module Operations
    # Per-org outcome reported via the progress block.
    #
    # @!attribute event [Symbol] One of :materialized, :would_materialize,
    #   :skipped_no_plan, :skipped_plan_filter,
    #   :failed_plan_not_found, :failed_org_write, :failed_cascade
    # @!attribute org_extid [String]
    # @!attribute planid [String, nil]
    # @!attribute entitlements_count [Integer, nil]
    # @!attribute cascade [Hash, nil] { success:, failed:, total: } when cascade ran
    # @!attribute reason [String, nil] Human-readable reason for skip/fail
    MaterializePlansEvent = Data.define(
      :event, :org_extid, :planid, :entitlements_count, :cascade, :reason,
    )

    # Aggregate result of MaterializePlans.call.
    #
    # Accounting invariant: an org appears in exactly one of
    # succeeded / failed / skipped_*. Cascade failures count the org as
    # failed (not succeeded) so partial-success is never masked.
    #
    # @!attribute scanned [Integer] Orgs iterated
    # @!attribute succeeded [Integer] Org write OK and (no cascade OR cascade fully OK)
    # @!attribute failed [Integer] Org write raised OR cascade had any failures
    # @!attribute skipped_no_plan [Integer] Org has empty planid
    # @!attribute skipped_plan_filter [Integer] Org not on --plan filter
    # @!attribute memberships_succeeded [Integer] Total memberships re-materialized
    # @!attribute memberships_failed [Integer] Total memberships that errored during cascade
    # @!attribute orgs_cascaded [Integer] Orgs where cascade was attempted
    # @!attribute errors [Array<Hash>] [{org_extid:, reason:}]
    MaterializePlansResult = Data.define(
      :scanned, :succeeded, :failed,
      :skipped_no_plan, :skipped_plan_filter,
      :memberships_succeeded, :memberships_failed, :orgs_cascaded,
      :errors,
    )

    # MaterializePlans — batch-materialize org entitlements from plan definitions,
    # with optional cascade to active memberships.
    #
    # Extracted from the CLI command so non-CLI callers (background jobs,
    # rake tasks, future admin UIs) can run the same logic with consistent
    # accounting and logging.
    #
    # The operation is idempotent: every in-scope org gets its entitlements
    # re-written from the plan definition on every run. An earlier "skip if
    # fresh" optimization was removed — the perf gain was minor, and pairing
    # it with --include-memberships caused cascades to be silently skipped
    # for up-to-date orgs (memberships can drift independently of the org's
    # entitlement set, so skipping them masked real consistency problems).
    #
    # Cascade semantics: when include_memberships is set and the org write
    # succeeded, org.rematerialize_all_memberships! runs. If that method
    # reports any membership failures, the org is counted as FAILED (with
    # the partial counts captured in the error reason). This intentionally
    # surfaces cascade problems rather than masking them as a "materialized"
    # success — operators decide whether to retry.
    #
    # Usage:
    #   result = Billing::Operations::MaterializePlans.call(dry_run: true)
    #   result = Billing::Operations::MaterializePlans.call(
    #     plan_filter: 'identity_plus_v1', include_memberships: true)
    #
    #   # With progress streaming (one yield per org):
    #   Billing::Operations::MaterializePlans.call do |event|
    #     puts "[#{event.event}] #{event.org_extid}"
    #   end
    class MaterializePlans
      DEFAULT_BATCH_SIZE = 100

      # @param plan_filter [String, nil] Only orgs whose planid matches this value
      # @param include_memberships [Boolean] Cascade to active memberships
      # @param dry_run [Boolean] Preview without writing
      # @param batch_size [Integer] each_record batch size
      # @param iterator [#each_record, nil] Override iteration source (testing)
      # @yieldparam event [MaterializePlansEvent] Per-org outcome
      # @return [MaterializePlansResult]
      def self.call(plan_filter: nil, include_memberships: false, dry_run: false,
                    batch_size: DEFAULT_BATCH_SIZE, iterator: nil, &progress_block)
        new(
          plan_filter: plan_filter,
          include_memberships: include_memberships,
          dry_run: dry_run,
          batch_size: batch_size,
          iterator: iterator,
          progress_block: progress_block,
        ).call
      end

      def initialize(plan_filter:, include_memberships:, dry_run:,
                     batch_size:, iterator:, progress_block:)
        @plan_filter         = plan_filter
        @include_memberships = include_memberships
        @dry_run             = dry_run
        @batch_size          = batch_size
        @iterator            = iterator || Onetime::Organization.instances
        @progress_block      = progress_block
        @counts              = Hash.new(0)
        @errors              = []
      end

      def call
        log_start
        plans_cache = preload_plans
        @iterator.each_record(batch_size: @batch_size) { |org| process_org(org, plans_cache) }
        result = build_result
        log_end(result)
        result
      end

      private

      def logger
        Onetime.billing_logger
      end

      # Preload all plans (~5) so no Redis reads happen inside the loop.
      def preload_plans
        plans = ::Billing::Plan.list_plans.to_h { |p| [p.plan_id, p] }
        logger.debug 'Preloaded plan cache', plan_ids: plans.keys, count: plans.size
        plans
      end

      def process_org(org, plans_cache)
        @counts[:scanned] += 1

        return if skip_for_plan_filter?(org)
        return if skip_for_no_plan?(org)

        plan = plans_cache[org.planid]
        return if missing_plan?(org, plan)

        if @dry_run
          emit(:would_materialize, org, planid: org.planid,
                                        entitlements_count: plan.entitlements.size)
          @counts[:succeeded] += 1
          return
        end

        materialize_and_cascade(org, plan)
      end

      def skip_for_plan_filter?(org)
        return false unless @plan_filter
        return false if org.planid.to_s == @plan_filter

        @counts[:skipped_plan_filter] += 1
        emit(:skipped_plan_filter, org, reason: "planid '#{org.planid}' != filter '#{@plan_filter}'")
        true
      end

      def skip_for_no_plan?(org)
        return false unless org.planid.to_s.empty?

        @counts[:skipped_no_plan] += 1
        emit(:skipped_no_plan, org, reason: 'Organization has no planid')
        logger.debug 'Skip org: no planid', org_extid: org.extid
        true
      end

      def missing_plan?(org, plan)
        return false if plan

        reason = "Plan '#{org.planid}' not found in catalog or config"
        @counts[:failed] += 1
        @errors << { org_extid: org.extid, reason: reason }
        emit(:failed_plan_not_found, org, planid: org.planid, reason: reason)
        logger.warn 'Plan not found in catalog or config',
          org_extid: org.extid, planid: org.planid
        true
      end

      def materialize_and_cascade(org, plan)
        org.materialize_entitlements_from_plan(plan)
        logger.debug 'Materialized org entitlements',
          org_extid: org.extid, planid: org.planid,
          entitlements_count: plan.entitlements.size
      rescue StandardError => ex
        record_org_write_failure(org, ex)
      else
        finalize_org_success(org, plan)
      end

      def finalize_org_success(org, plan)
        if @include_memberships
          cascade_outcome = run_cascade(org)
          return if cascade_outcome == :failed
        end

        @counts[:succeeded] += 1
        emit(:materialized, org, planid: org.planid,
                                 entitlements_count: plan.entitlements.size,
                                 cascade: @cascade_payload)
      ensure
        @cascade_payload = nil
      end

      def record_org_write_failure(org, ex)
        @counts[:failed] += 1
        @errors << { org_extid: org.extid, reason: "Org write failed: #{ex.message}" }
        emit(:failed_org_write, org, planid: org.planid, reason: ex.message)
        logger.error 'Org write failed',
          org_extid: org.extid, planid: org.planid, message: ex.message
        logger.debug 'Org write failed (backtrace)',
          org_extid: org.extid, backtrace: ex.backtrace&.join("\n")
      end

      # Cascade to memberships. Returns :ok or :failed.
      #
      # An org with any membership failures is counted as failed at the org
      # level so partial success doesn't masquerade as a clean run. The
      # successful-membership count is still aggregated for visibility.
      def run_cascade(org)
        cascade_result = org.rematerialize_all_memberships!

        @counts[:orgs_cascaded]            += 1
        @counts[:memberships_succeeded]    += cascade_result[:success]
        @counts[:memberships_failed]       += cascade_result[:failed]
        @cascade_payload                    = cascade_result

        if cascade_result[:failed].positive?
          handle_cascade_partial(org, cascade_result)
          :failed
        else
          logger.debug 'Cascade succeeded',
            org_extid: org.extid,
            memberships_total: cascade_result[:total],
            memberships_succeeded: cascade_result[:success]
          :ok
        end
      rescue StandardError => ex
        handle_cascade_exception(org, ex)
        :failed
      end

      def handle_cascade_partial(org, cascade_result)
        reason = "Cascade had #{cascade_result[:failed]}/#{cascade_result[:total]} membership failures"
        @counts[:failed] += 1
        @errors << { org_extid: org.extid, reason: reason }
        emit(:failed_cascade, org, planid: org.planid,
                                   cascade: cascade_result,
                                   reason: reason)
        logger.error 'Cascade had membership failures',
          org_extid: org.extid, planid: org.planid,
          memberships_total: cascade_result[:total],
          memberships_failed: cascade_result[:failed]
      end

      def handle_cascade_exception(org, ex)
        reason = "Cascade raised: #{ex.message}"
        @counts[:failed] += 1
        @errors << { org_extid: org.extid, reason: reason }
        emit(:failed_cascade, org, planid: org.planid, reason: reason)
        logger.error 'Cascade raised',
          org_extid: org.extid, planid: org.planid, message: ex.message
        logger.debug 'Cascade raised (backtrace)',
          org_extid: org.extid, backtrace: ex.backtrace&.join("\n")
      end

      def emit(event, org, planid: nil, entitlements_count: nil, cascade: nil, reason: nil)
        return unless @progress_block

        @progress_block.call(
          MaterializePlansEvent.new(
            event: event,
            org_extid: org.extid,
            planid: planid,
            entitlements_count: entitlements_count,
            cascade: cascade,
            reason: reason,
          ),
        )
      end

      def build_result
        MaterializePlansResult.new(
          scanned: @counts[:scanned],
          succeeded: @counts[:succeeded],
          failed: @counts[:failed],
          skipped_no_plan: @counts[:skipped_no_plan],
          skipped_plan_filter: @counts[:skipped_plan_filter],
          memberships_succeeded: @counts[:memberships_succeeded],
          memberships_failed: @counts[:memberships_failed],
          orgs_cascaded: @counts[:orgs_cascaded],
          errors: @errors,
        )
      end

      def log_start
        logger.info 'Materializing org entitlements from plan catalog',
          dry_run: @dry_run,
          plan_filter: @plan_filter,
          include_memberships: @include_memberships
      end

      def log_end(result)
        logger.info 'Materialization complete',
          dry_run: @dry_run,
          scanned: result.scanned,
          succeeded: result.succeeded,
          failed: result.failed,
          skipped_no_plan: result.skipped_no_plan,
          skipped_plan_filter: result.skipped_plan_filter,
          orgs_cascaded: result.orgs_cascaded,
          memberships_succeeded: result.memberships_succeeded,
          memberships_failed: result.memberships_failed
      end
    end
  end
end
