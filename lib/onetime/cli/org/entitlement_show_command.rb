# lib/onetime/cli/org/entitlement_show_command.rb
#
# frozen_string_literal: true

# Report an organization's entitlement state: plan baseline, operator overrides,
# what is actually materialized, and the drift between them.
#
# Usage:
#   bin/ots org entitlement show ORG
#   bin/ots org entitlement show ORG --json
#
# ORG is an org extid or objid (see Onetime::CLI::Org::Shared#resolve_org).
#
# ## Why this is its own command and not an `org doctor` check (D20)
#
# `org doctor` asserts invariants and offers repairs. This REPORTS state —
# different job, different exit-code contract (show always exits 0; a drifted
# org is a fact to look at, not a command failure).
#
# Without it, `org entitlement grant` is write-only from a shell: an operator
# has no way to see what an override did. That is the whole reason it ships in
# the same PR as the write verbs.
#
# ## Read-only, and deliberately no op
#
# There is nothing to audit and nothing to extract — this is a projection of
# model state. The shape is a straight port of
# ColonelAPI::Logic::Colonel::GetOrganizationDetail#build_entitlements so the
# shell and the admin console describe an org identically. Keep them in step.
require 'json'
require 'time'
require_relative 'shared'

module Onetime
  module CLI
    class OrgEntitlementShowCommand < Command
      include Org::Shared

      desc "Show an organization's plan / override / materialized entitlements + drift"

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid or objid'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        report       = build_entitlements(organization)

        json ? output_json(organization, report) : output_text(organization, report)
      end

      private

      # Current entitlement state + drift. `expected` mirrors the reconciliation
      # `apply_entitlements` performs (plan ∪ grants − revokes); `drift.extra` is
      # what materialized holds beyond that (orphans), `drift.missing` is what
      # should be materialized but isn't.
      #
      # PORTED VERBATIM in shape from GetOrganizationDetail#build_entitlements.
      def build_entitlements(org)
        plan_set     = org.entitlements_plan.to_a
        grants       = org.entitlements_grants.to_a
        revokes      = org.entitlements_revokes.to_a
        materialized = org.materialized_entitlements.to_a

        expected = ((plan_set | grants) - revokes)
        extra    = (materialized - expected).sort
        missing  = (expected - materialized).sort

        applied = org.materialized_entitlements_at_parsed

        {
          planid: org.planid.to_s,
          plan: plan_set.sort,
          grants: grants.sort,
          revokes: revokes.sort,
          materialized: materialized.sort,
          expected: expected.sort,
          materialized_flag: org.entitlements_materialized?,
          materialized_at: applied ? applied[:timestamp] : nil,
          plan_stale: compute_plan_stale(org),
          standalone: !org.billing_enabled?,
          drift: {
            extra: extra,
            missing: missing,
            in_sync: extra.empty? && missing.empty?,
          },
        }
      end

      # Plan-definition drift: has the plan's entitlement/limit content changed
      # since it was last materialized? Distinct from override drift above.
      # Returns nil when the plan can't be loaded (can't compare) rather than
      # asserting a state we can't verify.
      def compute_plan_stale(org)
        planid = org.planid.to_s
        return nil if planid.empty?
        return nil unless defined?(::Billing::Plan)

        plan = ::Billing::Plan.load(planid) || ::Billing::Plan.load_from_config(planid)
        return nil unless plan

        org.entitlements_stale?(plan)
      rescue StandardError
        nil
      end

      def output_text(organization, report)
        warn_standalone(report)

        puts "Organization: #{org_label(organization)}"
        puts "Plan:         #{report[:planid].empty? ? '(none)' : report[:planid]}"
        puts "Materialized: #{materialized_line(report)}"
        puts "Plan stale:   #{render_tristate(report[:plan_stale])}"
        puts
        print_set('Plan entitlements', report[:plan])
        print_set('Override grants', report[:grants])
        print_set('Override revokes', report[:revokes])
        print_set('Expected (plan + grants - revokes)', report[:expected])
        print_set('Materialized (what runtime reads)', report[:materialized])

        print_drift(report[:drift], organization.extid)
      end

      def materialized_line(report)
        return 'no' unless report[:materialized_flag]

        at = report[:materialized_at]
        at ? "yes (at #{Time.at(at).utc.iso8601})" : 'yes'
      end

      def render_tristate(value)
        return 'unknown (plan not loadable)' if value.nil?

        value ? 'YES — plan definition changed since materialization' : 'no'
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
        puts "Repair with: bin/ots org reconcile #{org_extid} --yes"
      end

      # Same dead-letter advisory the write verbs print, and it matters MORE
      # here: everything below reads the override sets directly, so on a
      # billing-disabled install this report shows overrides that no runtime
      # `can?` check will ever honour.
      def warn_standalone(report)
        return unless report[:standalone]

        warn 'WARNING: Billing is DISABLED on this install.'
        warn 'WARNING: Organization#entitlements returns STANDALONE_ENTITLEMENTS (full access)'
        warn 'WARNING: and never reads the sets below. This report describes stored state,'
        warn 'WARNING: not what the application actually enforces.'
      end

      def output_json(organization, report)
        puts JSON.pretty_generate(report.merge(org_id: organization.extid))
      end
    end

    register 'org entitlement show', OrgEntitlementShowCommand
  end
end
