# lib/onetime/cli/memberships/entitlement_show_command.rb
#
# frozen_string_literal: true

# Report a membership's entitlement state: role baseline, operator overrides,
# what is actually materialized, and the drift between them.
#
# Usage:
#   bin/ots memberships entitlement show ORG CUSTOMER
#   bin/ots memberships entitlement show ORG CUSTOMER --json
#
# ORG is an org extid (see Onetime::CLI::Memberships::Shared#resolve_org);
# CUSTOMER is an email, extid, or Rodauth account id.
#
# ## Read-only, and deliberately no op
#
# There is nothing to audit and nothing to extract — this is a projection of
# model state, the membership-scoped sibling of `org entitlement show` (D20):
# without it, `memberships entitlement grant` is write-only from a shell.
# Same exit-code contract: show always exits 0 once the membership resolves;
# a drifted membership is a fact to look at, not a command failure.
#
# `baseline_stale` is the membership analog of the org report's `plan_stale`:
# has the role baseline (org ∩ role template) drifted from the stored plan set
# since the last materialization? Both kinds of drift are repaired by
# `bin/ots org reconcile ORG --yes`, which cascades
# rematerialize_all_memberships! — overrides survive it by construction.
require 'json'
require 'time'
require_relative 'shared'
require_relative '../customers/shared'

module Onetime
  module CLI
    class MembershipsEntitlementShowCommand < Command
      include Customers::Shared
      include Memberships::Shared

      desc "Show a member's baseline / override / materialized entitlements + drift"

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid'
      argument :customer,
        type: :string,
        required: true,
        desc: 'Member email, extid, or Rodauth account ID'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, customer:, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'show entitlements for', json: json)
        membership   = resolve_membership(organization, member, json: json)
        report       = build_entitlements(organization, membership)

        json ? output_json(organization, member, report) : output_text(organization, member, report)
      end

      private

      # The membership itself must resolve — org + customer is its identity.
      # Exits 1 on a miss, matching the write verbs' :not_found rendering.
      def resolve_membership(organization, member, json:)
        membership = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, member.objid)
        unless membership&.active?
          error_exit("#{member.obscure_email} is not an active member of #{organization.extid}", json: json)
        end
        membership
      end

      # Current entitlement state + drift. `expected` mirrors the reconciliation
      # `apply_entitlements` performs (plan ∪ grants − revokes); `drift.extra` is
      # what materialized holds beyond that (orphans), `drift.missing` is what
      # should be materialized but isn't. Same shape as the org report
      # (`OrgEntitlementShowCommand#build_entitlements`) with membership axes:
      # `role` instead of `planid`, `baseline_stale` instead of `plan_stale`.
      def build_entitlements(org, membership)
        plan_set     = membership.entitlements_plan.to_a
        grants       = membership.entitlements_grants.to_a
        revokes      = membership.entitlements_revokes.to_a
        materialized = membership.materialized_entitlements.to_a

        expected = ((plan_set | grants) - revokes)
        extra    = (materialized - expected).sort
        missing  = (expected - materialized).sort

        applied = membership.materialized_entitlements_at_parsed

        {
          role: membership.role.to_s,
          plan: plan_set.sort,
          grants: grants.sort,
          revokes: revokes.sort,
          materialized: materialized.sort,
          expected: expected.sort,
          materialized_flag: membership.entitlements_materialized?,
          materialized_at: applied ? applied[:timestamp] : nil,
          baseline_stale: compute_baseline_stale(org, membership, plan_set),
          standalone: !org.billing_enabled?,
          drift: {
            extra: extra,
            missing: missing,
            in_sync: extra.empty? && missing.empty?,
          },
        }
      end

      # Role-baseline drift: does the stored plan set still equal what
      # materialize_for_role! would compute today (org ∩ role template)?
      # Distinct from override drift above. Returns nil when the role has no
      # template (can't compare) rather than asserting a state we can't verify.
      def compute_baseline_stale(org, membership, plan_set)
        role_template = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS[membership.role.to_s]
        return nil unless role_template

        baseline = (org.entitlements.to_set & role_template).to_a
        baseline.sort != plan_set.sort
      rescue StandardError
        nil
      end

      def output_text(organization, member, report)
        warn_standalone(report)

        puts "Organization: #{organization.extid}"
        puts "Member:       #{member.extid} (#{member.obscure_email})"
        puts "Role:         #{report[:role].empty? ? '(none)' : report[:role]}"
        puts "Materialized: #{materialized_line(report)}"
        puts "Baseline stale: #{render_tristate(report[:baseline_stale])}"
        puts
        print_set('Role baseline (org ∩ role template)', report[:plan])
        print_set('Override grants', report[:grants])
        print_set('Override revokes', report[:revokes])
        print_set('Expected (baseline + grants - revokes)', report[:expected])
        print_set('Materialized (what runtime reads)', report[:materialized])

        print_drift(report[:drift], organization.extid)
      end

      def materialized_line(report)
        return 'no' unless report[:materialized_flag]

        at = report[:materialized_at]
        at ? "yes (at #{Time.at(at).utc.iso8601})" : 'yes'
      end

      def render_tristate(value)
        return 'unknown (role template not loadable)' if value.nil?

        value ? 'YES — role baseline changed since materialization' : 'no'
      end

      def print_set(label, values)
        list = Array(values)
        puts "#{label} (#{list.size}):"
        if list.empty?
          puts '  (none)'
        else
          list.each { |value| puts "  - #{value}" }
        end
        puts
      end

      def print_drift(drift, org_extid)
        if drift[:in_sync]
          puts 'Drift: none — materialized matches expected.'
          return
        end

        puts 'Drift:'
        drift[:extra].each   { |e| puts "  + #{e}  (materialized but not expected — orphan)" }
        drift[:missing].each { |e| puts "  - #{e}  (expected but not materialized)" }
        puts
        puts "Repair with: bin/ots org reconcile #{org_extid} --yes  (re-materializes all memberships; overrides survive)"
      end

      # Membership scope softens the org-level dead-letter warning: the sets
      # below ARE read at runtime (no billing short-circuit on the membership
      # path), but the baseline they reconcile against is STANDALONE full role
      # access, so the report's grants mostly duplicate the baseline.
      def warn_standalone(report)
        return unless report[:standalone]

        warn 'WARNING: Billing is DISABLED on this install.'
        warn 'WARNING: The role baseline derives from STANDALONE_ENTITLEMENTS (full role'
        warn 'WARNING: access), so grants mostly add nothing while revokes still bite.'
      end

      def output_json(organization, member, report)
        puts JSON.pretty_generate(report.merge(org_id: organization.extid, member_id: member.extid))
      end
    end

    register 'memberships entitlement show', MembershipsEntitlementShowCommand
  end
end
