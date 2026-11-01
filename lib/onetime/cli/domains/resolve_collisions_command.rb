# lib/onetime/cli/domains/resolve_collisions_command.rb
#
# frozen_string_literal: true

# Decide and apply which custom domain record to keep when two or more share
# one DNS name (the collision groups `backfill-ascii-index` reports and
# never writes). Thin adapter over
# Onetime::Operations::Domains::CollisionResolution, which owns the facts, the
# rule, the plan file and the writes.
#
# Usage:
#   bin/ots domains resolve-collisions                       # plan: report the rule's decisions
#   bin/ots domains resolve-collisions --write plan.json     # plan, and save it for review and --apply
#   bin/ots domains resolve-collisions --json                # plan as JSON on stdout
#   bin/ots domains resolve-collisions --apply --plan plan.json --dry-run
#   bin/ots domains resolve-collisions --apply --plan plan.json            # confirm, then remove
#   bin/ots domains resolve-collisions --apply --plan plan.json --yes      # remove without prompting
#   bin/ots domains resolve-collisions --apply --plan plan.json --group demo.example
#
# STOP THE APPLICATION BEFORE --apply, as for backfill-ascii-index, and
# run that backfill's --apply afterwards: removing a record leaves the kept
# record's ASCII entry to the backfill. Runbook:
# docs/runbooks/custom-domain-ascii-index-backfill.md, step 6.
#
# Exit status: plan: 0 when no group needs an operator, 1 when a group still
# needs a keeper decision or deletion approval.
# apply: 0 when every group applied, 1 when a group was skipped or did not
# complete, or on refusal (declined prompt, --apply --json without --yes).

require 'json'
require 'onetime/operations/domains/collision_resolution'
require_relative '../customers/shared'
require_relative 'shared'

module Onetime
  module CLI
    class DomainsResolveCollisionsCommand < Command
      include Customers::Shared
      include Domains::Shared

      RUNBOOK = 'docs/runbooks/custom-domain-ascii-index-backfill.md'

      desc 'Plan and apply which record to keep for each custom-domain name collision (stop the app before --apply)'

      option :apply,
        type: :boolean,
        default: false,
        desc: 'Apply a plan file (requires --plan). Run only while the application is stopped'
      option :plan,
        type: :string,
        default: nil,
        desc: 'With --apply: the reviewed plan file (regenerate older rule-version plans)'
      option :write,
        type: :string,
        default: nil,
        desc: 'Without --apply: save the plan as JSON to this file'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'With --apply: check and preview without domain changes (preview audit entries may be written)'
      option :group,
        type: :string,
        default: nil,
        desc: 'With --apply: apply one group only, by its ASCII (A-label) name'
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y'],
        desc: 'With --apply: skip the confirmation prompt, not required plan-group approvals'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'
      option :help,
        type: :boolean,
        default: false,
        aliases: ['h'],
        desc: 'Show help message'

      def call(apply: false, plan: nil, write: nil, dry_run: false, group: nil, yes: false, json: false, help: false, **)
        return show_usage_help if help

        boot_application!

        if apply
          apply_plan(plan, dry_run: dry_run, group: group, yes: yes, json: json)
        else
          error_exit('--plan, --dry-run and --group go with --apply', json: json) if plan || dry_run || group
          make_plan(write: write, json: json)
        end
      end

      private

      def op
        Onetime::Operations::Domains::CollisionResolution.new
      end

      def make_plan(write:, json:)
        result = begin
          op.plan
        rescue StandardError => ex
          error_exit("Plan failed: #{ex.class}: #{ex.message}", json: json)
        end

        OT.info "[cli-domains-resolve-collisions] plan counts=#{result.counts}"

        File.write(write, "#{result.to_json}\n") if write
        if json
          puts result.to_json
        else
          puts Onetime::Operations::Domains::CollisionResolution::Text.plan(result)
          puts "Plan written to #{write}" if write
        end
        exit 1 if result.attention?
      end

      def apply_plan(path, dry_run:, group:, yes:, json:)
        error_exit('--apply requires --plan <file>', json: json) if path.to_s.empty?
        error_exit('Refusing to --apply in --json mode without --yes or --dry-run', json: true) if json && !yes && !dry_run

        plan = load_plan(path, json: json)
        if group && plan.group(group).nil?
          error_exit("Invalid --group: #{plan.missing_group_message(group)}", json: json)
        end
        confirm_apply(plan, group) unless yes || dry_run

        result = begin
          op.apply(plan, actor: Customers::Shared::CLI_ACTOR, dry_run: dry_run, only: group)
        rescue StandardError => ex
          error_exit("Apply failed: #{ex.class}: #{ex.message}", json: json)
        end

        OT.info "[cli-domains-resolve-collisions] dry_run=#{dry_run} counts=#{result.counts}"

        if json
          puts JSON.pretty_generate(result.to_h)
        else
          puts Onetime::Operations::Domains::CollisionResolution::Text.apply(result)
          puts "See #{RUNBOOK}." if result.attention?
        end
        exit 1 if result.attention?
      end

      def load_plan(path, json:)
        Onetime::Operations::Domains::CollisionResolution::Plan.parse(File.read(path))
      rescue Errno::ENOENT, Errno::EACCES => ex
        error_exit("Cannot read plan: #{ex.message}", json: json)
      rescue Onetime::Operations::Domains::CollisionResolution::InvalidPlan => ex
        error_exit("Invalid plan: #{ex.message}", json: json)
      end

      # Exits 1 unless the operator answers y.
      def confirm_apply(plan, group)
        groups   = group ? plan.groups.select { |g| g.ascii_name == group } : plan.groups
        removals = groups.reject { |g| g.skip || g.approval_pending? || (g.manual? && !g.keep) }
          .sum { |g| g.keep ? g.records.size - 1 : g.records.size }
        puts "This permanently removes up to #{removals} custom domain records in #{groups.size} groups,"
        puts 'with their configs and brand settings (deleted, not merged). Receipts retain share_domain.'
        puts 'Unapproved approval-required groups are excluded from this count and will be skipped.'
        puts 'An auto proposal can require billing approval; answering y or passing --yes does not approve it.'
        puts 'Evidence uses historical DNS confirmation and local cached billing, not fresh DNS or Stripe lookups.'
        puts 'The provider vhost for a name stays while a record for the name is kept.'
        puts 'The web, worker and scheduler processes must be stopped, and the datastore snapshotted.'
        print 'Is the application stopped, and the plan reviewed with required approvals saved? [y/N] '
        response = $stdin.gets&.strip&.downcase
        return if response == 'y'

        puts 'Aborted. Nothing was written.'
        exit 1
      end

      def show_usage_help
        puts <<~USAGE

          Custom domain name collisions: plan and apply which record to keep

          Usage:
            bin/ots domains resolve-collisions [--write FILE] [--json]
            bin/ots domains resolve-collisions --apply --plan FILE [--dry-run] [--yes] [--group NAME] [--json]

          Description:
            A collision is two or more custom domain records for one DNS name;
            backfill-ascii-index reports them and never writes them. Without
            --apply this command is read-only. For every record it gathers local
            name-index routing (served/shadow), historical DNS confirmation,
            ownership flags, organization identity/state, receipts, all configs,
            brand settings and cached billing. It makes no fresh DNS or Stripe
            lookup. Keeper selection is unchanged by billing, in this order:

              1. a record whose organization no longer exists is removed
              2. exactly one record with a historical passing TXT check on file is kept
              3. exactly one record with ownership verified is kept
              4. exactly one record in use (receipts, brand, sso or mailer config) is kept
              5. otherwise the record that answers for the name today, or the oldest

            A step that names several records marks the group manual. Save the
            plan with --write and review it. For each manual group set keep to
            the extid to keep and approved to true (or skip to true).

            Deletion also requires approved=true whenever a record to remove is
            billing-protected, even for an auto proposal. Billing source is always
            local_cache, never live Stripe. Active, trialing, past_due and unpaid
            subscriptions, or uncertain status with Stripe references/status,
            protect deletion, and so does an org_id that names no loadable
            organization (state dangling: an orphan whose billing cannot be read).
            Labels are live_or_recoverable, unknown, no_local_subscription and
            not_live. Billing never selects the keeper.
            --yes skips only the prompt; it does not approve any plan group.
            Older rule-version plans are rejected: regenerate and review them,
            rather than changing their version number.

            --apply skips groups missing required approval. For eligible groups,
            it removes the other records through the same operation as
            `domains remove`, re-enters the kept record in the
            exact name index when the removed record answered for the name, and
            on the Approximated strategy verifies the kept record again so its
            stored vhost status is current. The provider vhost is keyed by the
            name; the removals leave it in place for the kept record.
            Preflight checks every selected group before any removal. Unreadable
            audit records refuse the run; changed identity, billing, verification,
            routing or use evidence skips the group. An empty keep is allowed
            only for freshly confirmed all-orphans, and keep never names an
            orphan.

            Shared sender identities are retained, including references outside
            the selected groups. SendGrid/Lettermint identity checks read the
            provider's domain list once per provider per run, even during
            --dry-run; a sender domain the provider does not list has no
            identity to retain. Unreadable identities skip the group, and the
            reason names the record and whether its local mailer config or the
            provider lookup failed. Identities shared by multiple
            planned removals are also kept and may need manual provider cleanup
            afterwards.
            Configs and brand settings are deleted, not merged into the keeper;
            receipts retain share_domain. Run backfill-ascii-index --apply afterwards.

            Save the reviewed plan and console output. Apply reports include the
            run_id, plan timestamp, rule/approval, full saved record evidence,
            notes and actual removal/index/verification outcomes, even when a
            group is skipped. Non-dry apply records domain.resolve_collision per
            group and domain.remove per deletion in the admin audit trail.
            --dry-run makes no domain changes or collision-summary events.
            Removal previews are observations; preview failures may be audited.
            Failed previews and keeper refresh failures are partial outcomes
            (exit 1). Committed deletions stay in the report and are not rolled back.

          STOP THE APPLICATION BEFORE --apply. Snapshot the datastore first.
          Runbook: #{RUNBOOK}

          Options:
            --write FILE   Save the plan as JSON (plan mode)
            --apply        Apply a plan file
            --plan FILE    The plan to apply
            --dry-run      Check and preview without domain changes; may audit previews
            --group NAME   With --apply: one group, by ASCII name (a name not in the plan is refused)
            --yes, -y      Skip the prompt, not required plan-group approvals
            --json         JSON output (--apply --json requires --yes or --dry-run)
            --help, -h     Show this help

          Exit status:
            0  plan: no group needs an operator; apply: every group applied
            1  plan: a decision or deletion approval is pending; apply: a group was skipped or
               did not complete, or the run was refused

        USAGE
        true
      end
    end

    register 'domains resolve-collisions', DomainsResolveCollisionsCommand
  end
end
