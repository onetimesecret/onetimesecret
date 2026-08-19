# apps/api/colonel/logic/colonel/delete_organization.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'membership_resolvers'
require 'onetime/operations/org/delete'

module ColonelAPI
  module Logic
    module Colonel
      # Permanently delete an organization (Colonel) — the console peer of
      # `bin/ots org delete` (#4204).
      #
      # DELETE /api/colonel/organizations/:org_id
      #   ?dry_run=false             apply (the default is a PREVIEW)
      #   &force_default=true        override the default-workspace guard
      #   &force_subscription=true   override the active-subscription guard
      #
      # Thin adapter over {Onetime::Operations::Org::Delete} — the single,
      # audited implementation of the delete verb, shared with the CLI and with
      # the customer-facing `DELETE /api/organizations/:extid`. The op owns the
      # guardrails, the teardown, the `default_org_id` repair, the member
      # notifications and the ColonelAuditEvent; this class resolves the org and
      # threads three flags.
      #
      # ## Why the console gets this at all
      #
      # Support's actual case — "customer has two orgs, delete the free one" —
      # had no operator path: the customer-facing UI hides the button for a
      # default workspace and 403s without a materialized `manage_org`, and the
      # console had list/detail/investigate/reconcile/transfer-ownership but no
      # delete. Everything else in the org toolbox already has a console peer;
      # this closes the last hole, so an operator never has to reach for
      # `bin/console` (which corrupts `Organization.instances`).
      #
      # ## Parameters ride the QUERY STRING, not a body
      #
      # DELETE request bodies are not reliably parsed across this stack (same
      # reason `RemoveCustomDomain` reads `dry_run` from the query string), so
      # all three flags are query params. `dry_run` DEFAULTS TO TRUE: an apply
      # must say `dry_run=false` explicitly, and the screen must check
      # `details.dry_run` on the ack before it reports a deletion.
      #
      # ## Status mapping (deliberately asymmetric — read before "fixing")
      #
      # - A DRY RUN always answers 200, whatever the status. The preview IS the
      #   plan: it carries the members, invitations, domains, plan and owner the
      #   operator confirms against, plus the guardrail that would block the
      #   apply and whether an override exists for it. A 4xx here would throw
      #   away the very payload the console needs to render the confirmation.
      #   Nothing was written, so a 200 claims nothing.
      # - An APPLY that a guardrail refuses answers 4xx. Nothing was written, so
      #   a 200 would be a lie. This matches the transfer-ownership adapter,
      #   which has no preview flow and therefore refuses on every status.
      #
      # `record.deleted` is the single boolean the console should trust — it is
      # true only on an applied `:success`.
      #
      # ## Force flags are operator-only, and land in the audit trail
      #
      # `force_default` / `force_subscription` each unlock exactly one guard.
      # The op records which overrides were exercised in the
      # `organization.delete` event's detail, so a deleted default workspace or
      # a deleted billing org is visibly a decision someone made rather than a
      # guard that failed to run. The customer-facing adapter never passes them.
      # `:has_domains` and `:last_org` have no override on any surface.
      #
      # Audit: the op records exactly ONE `organization.delete` event per
      # applied delete, and none on a preview or a refusal (auditing refusals
      # would be a log-eviction primitive on the customer-facing adapter — see
      # the op). DO NOT audit here.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!) enforce the colonel role.
      class DeleteOrganization < ColonelAPI::Logic::Base
        include MembershipResolvers

        attr_reader :org, :dry_run, :force_default, :force_subscription, :result

        def process_params
          @org_id             = sanitize_identifier(params['org_id'])
          @dry_run            = params.key?('dry_run') ? truthy?(params['dry_run']) : true
          @force_default      = truthy?(params['force_default'])
          @force_subscription = truthy?(params['force_subscription'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?

          @org = resolve_org(@org_id)
          raise_not_found('Organization not found') unless @org&.exists?
        end

        def process
          @result = Onetime::Operations::Org::Delete.new(
            org: org,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            dry_run: dry_run,
            force_default: force_default,
            force_subscription: force_subscription,
            # The former members' mail says who did this; on the console that is
            # the acting colonel, not the org's own owner.
            deleted_by: cust.email,
          ).call

          # Log from the result: on the applied path destroy! empties the org's
          # in-memory fields, so `org.display_name` is gone by now.
          OT.info "[DeleteOrganization] #{result.org_id} (#{result.display_name}) -> " \
                  "status=#{result.status}, dry_run=#{dry_run}, members=#{result.members.size}"

          refuse_applied_guardrail unless dry_run

          # NOTE: no audit here — the op owns the single ColonelAuditEvent
          # (exactly-once, applied path only). This adapter never audits.
          success_data
        end

        # PUBLIC extids only. `record` is the identity + the one boolean worth
        # trusting; `details` is the op's Result echoed for the console's plan
        # screen. Key names mirror the CLI's --json payload so the two adapters
        # cannot drift.
        def success_data
          {
            record: {
              deleted: result.status == :success,
              org_id: result.org_id,
              display_name: result.display_name,
              status: result.status.to_s,
            },
            details: {
              dry_run: result.dry_run,
              planid: result.planid,
              members: result.members.map { |member| { extid: member[:extid], email: member[:email] } },
              members_notified: result.members_notified,
              pending_invitations: result.pending_invitations,
              domain_count: result.domain_count,
              domains: result.domains,
              is_default: result.is_default,
              active_subscription: result.active_subscription,
              owner_id: result.owner_id,
              owner_org_count: result.owner_org_count,
              default_org_cleared: result.default_org_cleared,
            },
          }
        end

        private

        # APPLY path only. A refused apply mutated nothing, so it must not
        # answer 200. Each message names the remediation and, where one exists,
        # the single flag that unlocks that guard.
        def refuse_applied_guardrail
          case result.status
          when :success
            nil # Fall through to success_data.
          when :has_domains
            raise_form_error(
              "Organization still has #{result.domain_count} domain(s)#{domain_names(result)}. " \
              'Remove them first.',
              field: :org_id,
            )
          when :is_default
            raise_form_error(
              'This is the owner\'s default (personal) workspace. Re-run with force_default=true to ' \
              'delete it anyway.',
              field: :force_default,
            )
          when :active_subscription
            raise_form_error(
              'Organization has an active subscription and nothing here cancels Stripe. Cancel the ' \
              'subscription first, or re-run with force_subscription=true to delete the org and leave ' \
              'the subscription billing.',
              field: :force_subscription,
            )
          when :last_org
            raise_form_error(
              "This is the only organization #{result.owner_id} belongs to; deleting it leaves them " \
              'with no workspace. There is no override.',
              field: :org_id,
            )
          else
            # :planned is impossible here (this branch runs only when dry_run is
            # false) — seeing it means the flag threading broke.
            raise Onetime::Problem, "Unexpected delete status: #{result.status}"
          end
        end

        # The count is authoritative; the names are best-effort (a stale entry in
        # the domains collection loads to nothing).
        def domain_names(result)
          return '' if result.domains.empty?

          ": #{result.domains.join(', ')}"
        end

        def truthy?(value)
          %w[true 1 yes on].include?(value.to_s.strip.downcase)
        end
      end
    end
  end
end
