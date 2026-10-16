# lib/onetime/cli/domains/resolve_collisions_command.rb
#
# frozen_string_literal: true

# Decide and apply which custom domain record to keep when two or more share
# one DNS name (the collision groups `backfill-canonical-index` reports and
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
# STOP THE APPLICATION BEFORE --apply, as for backfill-canonical-index, and
# run that backfill's --apply afterwards: removing a record leaves the kept
# record's canonical entry to the backfill. Runbook:
# docs/runbooks/custom-domain-canonical-index-backfill.md, step 6.
#
# Exit status: plan: 0 when no group needs an operator (no groups, or every
# group decided by the rule), 1 when a manual group is left undecided.
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

      RUNBOOK = 'docs/runbooks/custom-domain-canonical-index-backfill.md'

      desc 'Plan and apply which record to keep for each custom-domain name collision (stop the app before --apply)'

      option :apply,
        type: :boolean,
        default: false,
        desc: 'Apply a plan file (requires --plan). Run only while the application is stopped'
      option :plan,
        type: :string,
        default: nil,
        desc: 'With --apply: the plan file to apply'
      option :write,
        type: :string,
        default: nil,
        desc: 'Without --apply: save the plan as JSON to this file'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'With --apply: check the plan against the datastore and preview the removals; write nothing'
      option :group,
        type: :string,
        default: nil,
        desc: 'With --apply: apply one group only, by its canonical (A-label) name'
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y'],
        desc: 'With --apply: skip the confirmation prompt'
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
        groups   = group ? plan.groups.select { |g| g.canonical == group } : plan.groups
        removals = groups.reject { |g| g.skip || (g.manual? && !(g.approved && g.keep)) }
          .sum { |g| g.keep ? g.records.size - 1 : g.records.size }
        puts "This permanently removes up to #{removals} custom domain records in #{groups.size} groups,"
        puts 'with their configs and brand settings. The provider vhost for a name stays while a'
        puts 'record for the name is kept. The web, worker and scheduler processes must be'
        puts 'stopped, and the datastore snapshotted.'
        print 'Is the application stopped, and the plan reviewed? [y/N] '
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
            backfill-canonical-index reports them and never writes them. Without
            --apply this command gathers, for every record in a collision group,
            whether a request for the name resolves to it today, its DNS proof,
            its ownership flag, its organization's state, its receipts, its
            configs and brand settings, and decides the group by this rule:

              1. a record whose organization no longer exists is removed
              2. exactly one record with a passing TXT check on file is kept
              3. exactly one record with ownership verified is kept
              4. exactly one record in use (receipts, brand, sso or mailer config) is kept
              5. otherwise the record that answers for the name today, or the oldest

            A step that names several records marks the group manual. Save the
            plan with --write, review it, and for each manual group set keep to
            the extid to keep and approved to true (or skip to true).

            --apply removes the other records of every decided group through the
            same operation as `domains remove`, re-enters the kept record in the
            exact name index when the removed record answered for the name, and
            on the Approximated strategy verifies the kept record again so its
            stored vhost status is current. The provider vhost is keyed by the
            name; the removals leave it in place for the kept record. A group
            whose records changed since the plan is skipped. Run
            backfill-canonical-index --apply afterwards.

          STOP THE APPLICATION BEFORE --apply. Snapshot the datastore first.
          Runbook: #{RUNBOOK}

          Options:
            --write FILE   Save the plan as JSON (plan mode)
            --apply        Apply a plan file
            --plan FILE    The plan to apply
            --dry-run      With --apply: check and preview, write nothing
            --group NAME   With --apply: one group, by canonical name
            --yes, -y      With --apply: skip the confirmation prompt
            --json         JSON output (--apply --json requires --yes or --dry-run)
            --help, -h     Show this help

          Exit status:
            0  plan: no group needs an operator; apply: every group applied
            1  plan: a manual group is undecided; apply: a group was skipped or
               did not complete, or the run was refused

        USAGE
        true
      end
    end

    register 'domains resolve-collisions', DomainsResolveCollisionsCommand
  end
end
