# apps/api/colonel/logic/colonel/set_entitlement_preview.rb
#
# frozen_string_literal: true

require 'onetime/models/admin_audit_event'
require 'onetime/audited_failure'

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Set Entitlement Test Mode
      #
      # Allows colonels to override their organization's plan entitlements for testing.
      # The override is session-scoped and automatically cleared on logout.
      #
      # ## Phase 2 Implementation
      #
      # Test mode uses the reconciler with session-scoped grants/revokes stored
      # as plain Redis sets (not Familia). The reconciler computes:
      #   org.materialized_entitlements + session_grants - session_revokes
      #
      # "Reset and substitute" pattern:
      # - session_revokes = org's current entitlements (removes all)
      # - session_grants = test plan entitlements (adds test plan)
      #
      # ## Request
      #
      # POST /api/colonel/entitlement-preview
      # Body: { planid: "identity_plus_v1" }  - Set test mode
      #       { planid: null }                - Clear test mode
      #
      # ## Response
      #
      # Active override:
      # {
      #   status: "active",
      #   test_planid: "identity_plus_v1",
      #   test_plan_name: "Identity Plus",
      #   actual_planid: "free_v1",
      #   entitlements: ["create_secrets", "custom_domains", ...],
      #   source: "stripe" | "local_config"
      # }
      #
      # Cleared:
      # {
      #   status: "cleared",
      #   actual_planid: "free_v1"
      # }
      #
      # ## Security
      #
      # - Requires colonel role
      # - Session-scoped (cleared on logout)
      # - Does not modify actual subscription/billing
      #
      # ## Audited
      #
      # This mutates (redis del/sadd on session keys) and changes what the admin
      # sees, so it is a mutating admin op and records one event per call
      # (CONTRACT 4). The blast radius is the colonel's OWN session, so the
      # target is the acting colonel and `detail` stays minimal: the plan being
      # previewed, nothing else. No session key names, no entitlement lists.
      class SetEntitlementPreview < ColonelAPI::Logic::Base
        include Onetime::AuditedFailure

        AUDIT_VERB_SET   = 'entitlement_preview.set'
        AUDIT_VERB_CLEAR = 'entitlement_preview.clear'

        # Failure auditing (Onetime::AuditedFailure). Wraps #process, which Otto
        # runs AFTER #raise_concerns — so the colonel-role check and the invalid
        # -plan rejection that live there are structurally outside the audited
        # region, and an authorization rejection can never write an event.
        # `actor` is explicit: the ops' `@actor` default does not exist on a
        # Logic class.
        audit_failures :process,
          verb: -> { clearing? ? AUDIT_VERB_CLEAR : AUDIT_VERB_SET },
          target: -> { cust&.extid },
          actor: -> { cust&.extid }

        # TTL for session test mode Redis keys (matches session TTL)
        SESSION_TEST_TTL = 24 * 60 * 60 # 24 hours

        attr_reader :planid, :test_plan_config, :plan_source

        def process_params
          @planid = params['planid']&.to_s&.strip
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # If setting a plan, validate it exists
          return unless @planid && !@planid.empty?

          # Use centralized fallback loader
          result       = ::Billing::Plan.load_with_fallback(@planid)
          @plan_source = result[:source]

          if result[:plan]
            # Stripe-synced plan
            @test_plan_config = {
              name: result[:plan].name,
              entitlements: result[:plan].entitlements.to_a,
              limits: result[:plan].limits.hgetall || {},
            }
          elsif result[:config]
            # billing.yaml config plan
            @test_plan_config = {
              name: result[:config][:name],
              entitlements: result[:config][:entitlements],
              limits: result[:config][:limits],
            }
          else
            raise_form_error('Invalid plan ID')
          end
        end

        def process
          session_id = extract_session_id

          response = if session_id.nil?
                       process_without_reconciler
                     elsif clearing?
                       clear_test_mode(session_id)
                     else
                       set_test_mode(session_id)
                     end

          # One event per call, emitted here rather than inside the three
          # branches so the reconciler and the no-session fallback audit
          # identically.
          record_audit_event

          response
        end

        private

        # A blank/absent planid means "drop the preview" — the single source of
        # truth for the set-vs-clear branch AND for which verb is recorded, so
        # the two can't drift.
        def clearing?
          @planid.nil? || @planid.empty?
        end

        # Session-scoped, self-inflicted change: actor and target are both the
        # acting colonel. Detail carries the previewed plan and nothing else —
        # no session key names, no entitlement lists.
        def record_audit_event
          Onetime::AdminAuditEvent.record(
            actor: cust&.extid,
            verb: clearing? ? AUDIT_VERB_CLEAR : AUDIT_VERB_SET,
            target: cust&.extid,
            result: :success,
            detail: clearing? ? nil : { planid: @planid },
          )
        end

        def extract_session_id
          return nil unless sess

          sid = sess.id
          if sid.respond_to?(:public_id)
            sid.public_id
          elsif sid.is_a?(String)
            sid
          else
            sid.to_s
          end
        rescue StandardError
          nil
        end

        def session_grants_key(session_id)
          "session:#{session_id}:entitlement_preview_grants"
        end

        def session_revokes_key(session_id)
          "session:#{session_id}:entitlement_preview_revokes"
        end

        def clear_test_mode(session_id)
          redis = Familia.dbclient

          # Delete session test keys
          redis.del(session_grants_key(session_id))
          redis.del(session_revokes_key(session_id))

          # Clear session markers
          sess.delete(:entitlement_preview_grants_key)
          sess.delete(:entitlement_preview_revokes_key)
          sess.delete(:entitlement_preview_planid) # Legacy, for transition

          # Mirror into the request's Fiber-local: the middleware stashed the
          # pre-flip context before this handler ran, so without this the
          # response would serialize from stale preview state (ADR-020).
          Onetime::EntitlementPreview.clear

          {
            status: 'cleared',
            actual_planid: organization&.planid,
          }
        end

        def set_test_mode(session_id)
          redis       = Familia.dbclient
          grants_key  = session_grants_key(session_id)
          revokes_key = session_revokes_key(session_id)

          # Drop any in-flight preview context before reading the org:
          # organization.entitlements is preview-aware (ADR-020), and the
          # revokes set must capture the org's ACTUAL entitlements. Switching
          # preview from plan A to plan B would otherwise compute revokes from
          # plan A's reconciled view, leaking actual entitlements through the
          # new preview.
          Onetime::EntitlementPreview.clear

          # Get org's current entitlements (what we're "resetting" from)
          current_entitlements = if organization && organization.respond_to?(:entitlements)
                                   organization.entitlements
                                 else
                                   []
                                 end

          # Get test plan entitlements (what we're substituting)
          test_entitlements = @test_plan_config[:entitlements] || []

          # Store session revokes and grants using pipelined bulk operations
          redis.pipelined do |pipe|
            pipe.del(revokes_key)
            pipe.sadd(revokes_key, current_entitlements) if current_entitlements.any?
            pipe.expire(revokes_key, SESSION_TEST_TTL)

            pipe.del(grants_key)
            pipe.sadd(grants_key, test_entitlements) if test_entitlements.any?
            pipe.expire(grants_key, SESSION_TEST_TTL)
          end

          # Store key names and planid in session for middleware
          sess[:entitlement_preview_grants_key]  = grants_key
          sess[:entitlement_preview_revokes_key] = revokes_key
          sess[:entitlement_preview_planid]      = @planid

          # Mirror into the request's Fiber-local so this response — and
          # anything else serialized after the flip — reflects the new
          # preview state (ADR-020).
          Onetime::EntitlementPreview.set(
            planid: @planid,
            grants_key: grants_key,
            revokes_key: revokes_key,
          )

          {
            status: 'active',
            test_planid: @planid,
            test_plan_name: @test_plan_config[:name],
            actual_planid: organization&.planid,
            entitlements: test_entitlements,
            limits: @test_plan_config[:limits],
            source: @plan_source,
          }
        end

        # Fallback for when session ID extraction fails
        def process_without_reconciler
          if @planid.nil? || @planid.empty?
            sess.delete(:entitlement_preview_planid)
            Onetime::EntitlementPreview.clear
            {
              status: 'cleared',
              actual_planid: organization&.planid,
            }
          else
            sess[:entitlement_preview_planid] = @planid
            # Planid-only context: limits preview works, entitlement
            # reconciliation stays inactive (no grants/revokes keys).
            Onetime::EntitlementPreview.set(
              planid: @planid,
              grants_key: nil,
              revokes_key: nil,
            )
            {
              status: 'active',
              test_planid: @planid,
              test_plan_name: @test_plan_config[:name],
              actual_planid: organization&.planid,
              entitlements: @test_plan_config[:entitlements],
              limits: @test_plan_config[:limits],
              source: @plan_source,
            }
          end
        end
      end
    end
  end
end
