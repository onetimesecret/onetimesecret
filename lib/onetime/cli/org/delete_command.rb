# lib/onetime/cli/org/delete_command.rb
#
# frozen_string_literal: true

# Permanently delete an organization.
#
# Usage:
#   bin/ots org delete ORG                      # plan, confirm, apply
#   bin/ots org delete ORG --yes                # skip the prompt
#   bin/ots org delete ORG --dry-run            # plan only (wins over --yes)
#   bin/ots org delete ORG --yes --json         # machine-readable
#   bin/ots org delete ORG --yes --force-default        # delete a default workspace
#   bin/ots org delete ORG --yes --force-subscription   # delete a billing org
#
# ORG is an org extid or objid (Onetime::CLI::Org::Shared#resolve_org).
#
# Without --yes the command runs a DRY RUN first and prints the plan — display
# name, plan, members and their emails, pending invitations, and every
# `default_org_id` the delete will clear — before asking to confirm. Answering
# `n` is therefore also how you preview a delete.
#
# ## Guardrails
#
# The op refuses (non-zero exit, nothing written) on four conditions. Two have
# an override, and each override unlocks ONLY the guard it names:
#
#   has_domains          remove the domains first (`bin/ots domains remove`).
#                        No override: `destroy!` raises on domains anyway.
#   is_default           --force-default. A default workspace is the owner's
#                        personal workspace; the product promises a "contact us"
#                        flow instead of a delete.
#   active_subscription  --force-subscription. NOTHING HERE TOUCHES STRIPE — the
#                        subscription keeps billing after a forced delete. Cancel
#                        it first unless you know otherwise.
#   last_org             no override. The owner would be left with no workspace;
#                        create the replacement org first, or purge the account
#                        with `bin/ots customers purge-one`.
#
# ## This is not `bin/console`
#
# A hand-run `Organization#destroy!` is NOT equivalent: it leaves the org in
# `Organization.instances` (which `org doctor --all`, `memberships` counting and
# the org list all walk), never mails the former members, and never repoints
# `default_org_id`. The op behind this command does all three. Use this command.
#
# The mutation + the admin audit event are performed by the shared
# Onetime::Operations::Org::Delete op (the single implementation, also behind
# `DELETE /api/colonel/organizations/:org_id` and the customer-facing
# `DELETE /api/organizations/:extid`). This command owns only CLI concerns. The
# CLI runs outside the app autoloaders, so require the op explicitly.
require 'json'
require 'onetime/operations/org/delete'
# Org::Shared / Customers::Shared must exist before the `include`s below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../customers/shared'

module Onetime
  module CLI
    class OrgDeleteCommand < Command
      # Customers::Shared -> the CLI_ACTOR sentinel.
      # Org::Shared       -> resolve_org + error_exit (json-aware) + org_label.
      include Customers::Shared
      include Org::Shared

      desc 'Permanently delete an organization'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid or objid'

      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Show the deletion plan without mutating (wins over --yes)'
      option :force_default,
        type: :boolean,
        default: false,
        desc: 'Delete even when the org is a default (personal) workspace'
      option :force_subscription,
        type: :boolean,
        default: false,
        desc: 'Delete even with an active subscription (never cancels Stripe)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, yes: false, dry_run: false, force_default: false,
               force_subscription: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        @force       = { force_default: force_default, force_subscription: force_subscription }

        # Never destroy production state from a scripted invocation that did not
        # say so. --dry-run is exempt: it writes nothing by construction.
        if json && !yes && !dry_run
          error_exit('Refusing to delete without --yes in --json mode', json: true)
        end

        result =
          if dry_run
            run_op(organization, dry_run: true)
          elsif yes
            run_op(organization, dry_run: false)
          else
            confirm_and_apply(organization)
          end

        return if result.nil? # operator declined at the prompt

        OT.info "[cli-org-delete] org=#{result.org_id} status=#{result.status} " \
                "dry_run=#{result.dry_run} members=#{result.members.size}"

        json ? output_json(result) : output_text(result)
      end

      private

      def run_op(organization, dry_run:)
        Onetime::Operations::Org::Delete.new(
          org: organization,
          # Never fabricate a Customer for the shell (ADR-023) — the audit trail
          # records the shared CLI sentinel.
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: dry_run,
          **@force,
        ).call
      end

      # Two op calls: plan, then apply. Interactive path only.
      #
      # @return [Onetime::Operations::Org::Delete::Result, nil] nil when the
      #   operator declines.
      def confirm_and_apply(organization)
        plan = run_op(organization, dry_run: true)

        # A guardrail tripped: there is nothing to confirm. Report the refusal
        # verbatim (exit 1) rather than prompting for a delete that cannot run.
        return plan unless plan.status == :planned

        print_plan(plan)

        print "Permanently delete #{org_label(organization)}? [y/N] "
        response = $stdin.gets&.strip&.downcase
        return run_op(organization, dry_run: false) if response == 'y'

        puts 'Aborted.'
        nil
      end

      # The confirmation screen. It must name everything the delete destroys, so
      # an operator can catch a wrong ORG before they answer.
      def print_plan(plan)
        puts 'DRY RUN — nothing has been written yet'
        puts "Organization:   #{plan.org_id} (#{plan.display_name})"
        puts "Plan:           #{plan.planid}#{subscription_suffix(plan)}"
        puts "Owner:          #{owner_line(plan)}"
        puts "Members:        #{plan.members.size}"
        plan.members.each { |member| puts "  - #{member[:extid]}  #{member[:email]}" }
        puts "Invitations:    #{plan.pending_invitations} pending (revoked by the delete)"
        puts "Domains:        #{domain_summary(plan)}"
        puts "Notifications:  #{plan.members_notified} member(s) emailed after deletion"
        puts "default_org_id: #{default_org_line(plan)}"
        puts 'Default workspace: YES (--force-default in effect)' if plan.is_default
        puts
      end

      # The count is authoritative (it is what `destroy!` refuses on); the names
      # are best-effort and come up short when the domains collection carries a
      # stale entry.
      def domain_summary(plan)
        return 'none' if plan.domain_count.zero?
        return "#{plan.domain_count} (names unavailable — run bin/ots domains doctor)" if plan.domains.empty?

        "#{plan.domains.join(', ')} (#{plan.domain_count})"
      end

      def subscription_suffix(plan)
        plan.active_subscription ? ' (LIVE SUBSCRIPTION — Stripe is NOT cancelled)' : ''
      end

      def owner_line(plan)
        return '(none — owner_id points at no live customer)' if plan.owner_id.nil?

        "#{plan.owner_id} (member of #{plan.owner_org_count} organization(s))"
      end

      def default_org_line(plan)
        return 'no customer points at this org' if plan.default_org_cleared.empty?

        "cleared for #{plan.default_org_cleared.join(', ')}"
      end

      def output_text(result)
        refuse(result) unless Onetime::Operations::Org::Delete::OK_STATUSES.include?(result.status)

        if result.status == :planned
          print_plan(result)
          puts 'Dry run only — re-run without --dry-run to apply.'
          return
        end

        puts "Deleted #{result.org_id} (#{result.display_name})"
        puts "  members notified:    #{result.members_notified}/#{result.members.size}"
        puts "  invitations revoked: #{result.pending_invitations}"
        return if result.default_org_cleared.empty?

        puts "  default_org_id cleared: #{result.default_org_cleared.join(', ')}"
      end

      def output_json(result)
        payload = {
          status: result.status,
          org_id: result.org_id,
          display_name: result.display_name,
          planid: result.planid,
          members: result.members,
          members_notified: result.members_notified,
          pending_invitations: result.pending_invitations,
          domain_count: result.domain_count,
          domains: result.domains,
          is_default: result.is_default,
          active_subscription: result.active_subscription,
          owner_id: result.owner_id,
          owner_org_count: result.owner_org_count,
          default_org_cleared: result.default_org_cleared,
          dry_run: result.dry_run,
        }
        puts JSON.pretty_generate(payload)
        exit 1 unless Onetime::Operations::Org::Delete::OK_STATUSES.include?(result.status)
      end

      # Refusal statuses render the SAME operator guidance on the plan pass and
      # the applied pass, so a --yes run and an interactive run cannot drift.
      # Each names the remediation, and only the override that unlocks that one
      # guard.
      def refuse(result)
        case result.status
        when :has_domains
          error_exit(
            "#{result.org_id} still has #{result.domain_count} domain(s): #{domain_summary(result)}. " \
            'Run: bin/ots domains remove DOMAIN for each, then retry',
            json: false,
          )
        when :is_default
          error_exit(
            "#{result.org_id} is a default (personal) workspace. Deleting it leaves the owner " \
            'without their workspace — the product routes these to support instead. ' \
            'Re-run with --force-default if that is genuinely what you want',
            json: false,
          )
        when :active_subscription
          error_exit(
            "#{result.org_id} has an active subscription. Nothing here cancels Stripe: cancel the " \
            'subscription first, or re-run with --force-subscription to delete the org and leave ' \
            'the subscription billing',
            json: false,
          )
        when :last_org
          error_exit(
            "#{result.org_id} is the only organization #{result.owner_id} belongs to; deleting it " \
            'leaves them with no workspace. Create the replacement org first (bin/ots org create), ' \
            'or purge the account (bin/ots customers purge-one). There is no override',
            json: false,
          )
        else
          error_exit("Delete failed: #{result.status}", json: false)
        end
      end
    end

    register 'org delete', OrgDeleteCommand
  end
end
