# apps/web/auth/operations/customers/purge.rb
#
# frozen_string_literal: true

require 'auth/operations/teardown_account'
require 'auth/operations/customers/purge_preflight'
require 'auth/operations/customers/membership_snapshot'
require 'onetime/operations/org/delete'
require 'onetime/operations/memberships/remove'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/audit_reason'
require 'onetime/operations/bulk_audit_context'

module Auth
  module Operations
    module Customers
      # ADMIN purge of a single account. Organization references are planned and
      # validated read-only before any session, Rodauth, organization, membership,
      # or customer mutation. Only a strictly empty personal default workspace is
      # deleted automatically; consistent non-owner memberships are removed.
      class Purge
        include Onetime::AuditedFailure
        include Onetime::AuditReason

        AUDIT_VERB = 'customer.purge'

        # Self-service deletion is excluded: an unhandled exception on that path
        # is already logged by the close-account hook, and routing it here would
        # put a user-triggered write on the operator trail. See #audit_enabled?.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @customer&.extid },
          detail: -> { failure_audit_detail },
          enabled: -> { !@self_service && audit_enabled? }

        # Backward-compatible initializer: existing adapters constructing Result
        # with status/extid/custid continue to work while new callers can inspect
        # blockers, actions, and the last completed stage.
        class Result
          attr_reader :status,
            :extid,
            :custid,
            :blockers,
            :actions,
            :planned_actions,
            :stage,
            :completed_stages

          def initialize(status:, extid:, custid:, blockers: [], actions: [], planned_actions: [],
                         stage: nil, completed_stages: [])
            @status           = status
            @extid            = extid
            @custid           = custid
            @blockers         = blockers.freeze
            @actions          = actions.freeze
            @planned_actions  = planned_actions.freeze
            @stage            = stage
            @completed_stages = completed_stages.freeze
            freeze
          end
        end

        # @param self_service [Boolean] the ACCOUNT ITSELF asked for this, via
        #   /auth/close-account or the simple-mode delete endpoint. Two things
        #   change. The actor defaults to the customer, so events are attributed
        #   instead of landing as 'unknown'. And events go to the security trail
        #   rather than the operator trail: the operator trail is capped at
        #   MAX_EVENTS and trimmed oldest-first, so a user who can retry a
        #   deletion at will must not be able to write to it. Refusals, which are
        #   the unbounded case, are logged only.
        # @param deep [Boolean] run the operator-grade global registry sweep in
        #   preflight. Off on request paths; see PurgePreflight#initialize.
        # @param membership_snapshot [MembershipSnapshot, nil] the membership
        #   registry captured once by a bulk run, so every shallow preflight of
        #   this purge sees rows the organization's own `members` set lost.
        # @param sweep_untracked_sessions [Boolean] let session revocation walk
        #   the session keyspace for pre-sidecar blobs the tracked index never
        #   saw. That walk is one bounded SCAN plus a decrypt per key, PER
        #   ACCOUNT; a bulk inactivity sweep turns it off because its candidates
        #   have been idle for months and every blob they could own has
        #   expired. The tracked revocation still runs.
        def initialize(customer:, actor: nil, reason: nil, bulk_audit_context: nil,
                       expected_plan_signature: nil,
                       self_service: false, deep: false, membership_snapshot: nil,
                       sweep_untracked_sessions: true)
          @customer                 = customer
          @self_service             = self_service
          @deep                     = deep
          @membership_snapshot      = membership_snapshot
          @sweep_untracked_sessions = sweep_untracked_sessions
          @actor                    = actor || (self_service ? customer : nil)
          @reason                   = normalize_reason(reason)
          @bulk_audit_context       = bulk_audit_context
          @expected_plan_signature  = expected_plan_signature
          @stage                    = :initialized
          @completed_actions        = []
          @completed_stages         = []
          @planned_actions          = []
          @mutation_started         = false
        end

        def mutation_started?
          @mutation_started
        end

        def outcome_context
          {
            stage: @stage,
            actions: @completed_actions.dup,
            completed_stages: @completed_stages.dup,
          }
        end

        # @return [Result] :success, :refused, :partial, or :not_found
        def call
          extid  = @customer.extid
          custid = @customer.custid

          @stage  = :preflight
          initial = preflight(deep: @deep)
          # Authorization precedes the first refusal so a refused candidate
          # never consumes an operator-trail slot; the bulk receipt records the
          # refused count. A bulk run registers every candidate up front, and a
          # refusal is the common outcome of an inactivity sweep, so per-refusal
          # events would trim the capped trail by the size of the run.
          authorize_bulk_audit(initial)
          return refused_result(initial, extid, custid) unless initial.executable?
          if @expected_plan_signature && initial.signature != @expected_plan_signature
            return refused_result(
              initial,
              extid,
              custid,
              blockers: [{ code: :preflight_changed }],
            )
          end

          @planned_actions = initial.action_details
          cleanup_result   = apply_cleanup(initial, extid, custid)
          return cleanup_result if cleanup_result

          @stage   = :post_cleanup_revalidation
          residual = preflight
          unless same_remaining_plan?(residual, [])
            blockers = residual.blockers.dup
            blockers << { code: :preflight_changed } if residual.signature != signature_for([])
            blockers << { code: :references_remain } if residual.actions.any?
            return partial_or_refused_result(extid, custid, blockers: blockers)
          end
          complete_stage(:organization_cleanup)

          # This is the immediate revalidation for the account mutation group:
          # TeardownAccount revokes sessions, closes Rodauth, then deletes Redis.
          @stage   = :account_teardown
          deletion = Auth::Operations::TeardownAccount.new(
            customer: @customer,
            actor: @actor,
            reason: @reason,
            before_mutation: method(:revalidate_account_mutation),
            on_mutation: method(:mark_mutation_started),
            bulk_audit_context: @bulk_audit_authorization,
            sweep_untracked_sessions: @sweep_untracked_sessions,
            self_service: @self_service,
          ).call
          deletion.completed_stages.each { |completed| complete_stage(completed) }
          unless deletion.status == :success
            blockers = @teardown_blockers || [
              {
                code: :customer_not_deleted,
                blocked_stage: deletion.blocked_stage,
                teardown_status: deletion.status,
              },
            ]
            return partial_result(extid, custid, blockers: blockers) if deletion.status == :partial || @completed_actions.any?
            return partial_or_refused_result(extid, custid, blockers: blockers) if deletion.status == :refused

            return result(:not_found, extid, custid, blockers: blockers)
          end

          complete_stage(:account_teardown)

          # Redis/SQL are not atomic. Scan again after teardown so a concurrent
          # organization write cannot be reported as a successful clean purge.
          @stage   = :post_teardown_revalidation
          residual = preflight(deep: @deep)
          unless same_remaining_plan?(residual, [])
            blockers = residual.blockers.dup
            blockers << { code: :preflight_changed } if residual.signature != signature_for([])
            blockers << { code: :references_remain } if residual.actions.any?
            return partial_result(extid, custid, blockers: blockers)
          end
          complete_stage(:reference_cleanup)

          if audit_enabled?
            @stage = :customer_audit
            record_audit_event(
              target: extid,
              result: :success,
              detail: with_reason(email: obscure(@customer)),
              fail_closed: true,
            )
            complete_stage(:customer_audit)
          end
          @stage = :complete
          result(:success, extid, custid)
        end

        private

        def audit_enabled?
          !Onetime::Operations::BulkAuditContext.verified?(
            @bulk_audit_authorization,
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer&.extid,
            operation: self,
          )
        end

        # Runs on the initial plan whether or not it is executable, ahead of the
        # first refusal, so a refused candidate never writes its own
        # operator-trail event. Consuming the candidate slot on a refusal is
        # correct because each candidate is purged once per run.
        def authorize_bulk_audit(plan)
          return unless @bulk_audit_context.instance_of?(Onetime::Operations::BulkAuditContext)

          operations = [
            { verb: AUDIT_VERB, target: @customer.extid },
            {
              verb: Onetime::Operations::Sessions::RevokeAllForCustomer::AUDIT_VERB,
              target: @customer.extid,
            },
          ]
          plan.actions.each do |action|
            case action.type
            when :delete_organization
              operations << {
                verb: Onetime::Operations::Org::Delete::AUDIT_VERB,
                target: action.org_id,
              }
            when :remove_membership
              operations << {
                verb: Onetime::Operations::Memberships::Remove::AUDIT_VERB,
                target: @customer.extid,
                scope: action.org_id,
              }
            end
          end

          @bulk_audit_authorization = @bulk_audit_context.authorize_candidate(
            customer_target: @customer.objid,
            operations: operations,
          )
        end

        def mark_mutation_started(_stage)
          @mutation_started = true
        end

        def track_cleanup_mutation
          previously_started = @mutation_started
          @mutation_started  = true
          operation_result   = yield
          @mutation_started  = previously_started unless operation_result.status == :success
          operation_result
        end

        # Revalidation between mutations is deliberately SHALLOW even when the
        # caller asked for a deep sweep: the operator-grade registry scan runs at
        # the two boundaries that matter (the initial plan and the final
        # post-teardown check) rather than once per action.
        def preflight(deep: false)
          Auth::Operations::Customers::PurgePreflight.new(
            customer: @customer,
            deep: deep,
            membership_snapshot: @membership_snapshot,
          ).call
        end

        def apply_cleanup(plan, extid, custid)
          remaining = plan.actions.dup

          until remaining.empty?
            @stage    = :cleanup_revalidation
            validated = preflight
            unless same_remaining_plan?(validated, remaining)
              blockers = validated.blockers.dup
              blockers << { code: :preflight_changed } if validated.signature != signature_for(remaining)
              return partial_or_refused_result(extid, custid, blockers: blockers)
            end

            # Use the freshly loaded action rather than an object snapshotted by
            # the initial preflight.
            action           = validated.actions.first
            @stage           = action.type
            operation_result = case action.type
                               when :delete_organization then delete_organization(action)
                               when :remove_membership then remove_membership(action)
                               else
                                 return partial_or_refused(
                                   extid,
                                   custid,
                                   code: :unknown_cleanup_action,
                                   action: action.type,
                                 )
                               end

            unless operation_result.status == :success
              return partial_or_refused(
                extid,
                custid,
                code: :cleanup_refused,
                org_id: action.org_id,
                action: action.type,
                operation_status: operation_result.status,
              )
            end

            @completed_actions << action.public_detail(status: :success)
            complete_stage(action.type)
            remaining.shift
          end

          nil
        end

        def delete_organization(action)
          operation = Onetime::Operations::Org::Delete.new(
            org: action.organization,
            actor: @actor,
            dry_run: false,
            account_purge_context: action.account_purge_context,
            reason: @reason,
            bulk_audit_context: @bulk_audit_authorization,
            self_service: @self_service,
          )
          track_cleanup_mutation { operation.call }
        end

        def remove_membership(action)
          operation = Onetime::Operations::Memberships::Remove.new(
            org: action.organization,
            customer: @customer,
            actor: @actor,
            reason: @reason,
            bulk_audit_context: @bulk_audit_authorization,
            self_service: @self_service,
          )
          track_cleanup_mutation { operation.call }
        end

        def refused_result(plan, extid, custid, blockers: plan.blockers)
          @planned_actions = plan.action_details
          record_unsuccessful(:refused, blockers, fail_closed: false)
          result(:refused, extid, custid, blockers: blockers)
        end

        def partial_or_refused(extid, custid, **blocker)
          partial_or_refused_result(extid, custid, blockers: [blocker])
        end

        def partial_or_refused_result(extid, custid, blockers:)
          if @completed_actions.empty?
            record_unsuccessful(:refused, blockers, fail_closed: false)
            result(:refused, extid, custid, blockers: blockers)
          else
            partial_result(extid, custid, blockers: blockers)
          end
        end

        def partial_result(extid, custid, blockers:)
          record_unsuccessful(:partial, blockers, fail_closed: true)
          result(:partial, extid, custid, blockers: blockers)
        end

        # Two unbounded refusal sources are kept off the capped operator trail:
        # a bulk candidate (covered by the run's receipt, see #audit_enabled?)
        # and the self-service path below.
        def record_unsuccessful(status, blockers, fail_closed:)
          return unless audit_enabled?

          # A refusal on the self-service path is user-triggered and unbounded —
          # a blocked account can produce one per click. Log it; never let it
          # consume a capped audit slot.
          if @self_service && status == :refused
            OT.info '[customer.purge] self-service deletion refused',
              external_id: @customer.extid,
              stage: @stage.to_s,
              blocker_codes: blockers.map { |blocker| blocker[:code].to_s }.uniq
            return
          end

          detail = with_reason(
            status: status.to_s,
            stage: @stage.to_s,
            blocker_codes: blockers.map { |blocker| blocker[:code].to_s }.uniq,
            completed_actions: @completed_actions,
            completed_stages: @completed_stages.map(&:to_s),
          )
          record_audit_event(
            target: @customer.extid,
            result: :failure,
            detail: detail,
            fail_closed: fail_closed,
          )
        end

        # Operator actions go to the capped operator trail with its fail-closed
        # contract; self-service deletions go to the security trail, which exists
        # precisely so a separate write budget protects the operator trail.
        def record_audit_event(target:, result:, detail:, fail_closed:)
          if @self_service
            Onetime::ColonelAuditEvent.record_security(
              actor: @actor,
              verb: AUDIT_VERB,
              target: target,
              result: result,
              detail: detail,
            )
          else
            Onetime::ColonelAuditEvent.record(
              actor: @actor,
              verb: AUDIT_VERB,
              target: target,
              result: result,
              detail: detail,
              fail_closed: fail_closed,
            )
          end
        end

        def result(status, extid, custid, blockers: [], actions: @completed_actions)
          Result.new(
            status: status,
            extid: extid,
            custid: custid,
            blockers: blockers,
            actions: actions,
            planned_actions: @planned_actions,
            stage: @stage,
            completed_stages: @completed_stages,
          )
        end

        def revalidate_account_mutation(stage)
          @stage = :"account_teardown_#{stage}"
          plan   = preflight
          return true if same_remaining_plan?(plan, [])

          @teardown_blockers = plan.blockers.dup
          @teardown_blockers << { code: :preflight_changed, blocked_stage: stage }
          @teardown_blockers << { code: :references_remain, blocked_stage: stage } if plan.actions.any?
          false
        end

        def same_remaining_plan?(plan, remaining)
          plan.executable? && plan.signature == signature_for(remaining)
        end

        def signature_for(actions)
          Auth::Operations::Customers::PurgePreflight::Plan.new(
            actions: actions,
            blockers: [],
          ).signature
        end

        def complete_stage(stage)
          @completed_stages << stage unless @completed_stages.include?(stage)
        end

        def failure_audit_detail
          {
            stage: @stage.to_s,
            completed_actions: @completed_actions.size,
            completed_stages: @completed_stages.map(&:to_s),
          }
        end

        def obscure(customer)
          customer.obscure_email
        rescue StandardError
          nil
        end
      end
    end
  end
end
