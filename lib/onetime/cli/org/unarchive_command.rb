# lib/onetime/cli/org/unarchive_command.rb
#
# frozen_string_literal: true

# Restore an archived organization.
#
# Usage:
#   bin/ots org unarchive ORG                   # dry run (the default): show what would be cleared
#   bin/ots org unarchive ORG --run             # apply
#   bin/ots org unarchive ORG --run --json      # machine-readable
#
# ORG is an org extid or objid (Onetime::CLI::Org::Shared#resolve_org).
#
# Unlike `org delete` / `org transfer-ownership` there is no confirmation
# prompt: the default IS the dry run, and --run is the explicit apply (the
# `bin/ots migrations …` convention). The op is constructed exactly once per
# invocation.
#
# ## Statuses
#
#   not_archived  the org is live; exit 0, nothing written.
#   planned       dry run; exit 0, nothing written.
#   success       applied; exit 0.
#
# There is no refusal. When the owner's default_org_id names a different live
# organization, both passes print one advisory line naming it: the sign-in
# self-heal archives only the workspace the owner's pointer resolves to, so a
# pointer at another live org leaves this one untouched after the repair, but
# the owner will not land here until someone repoints it.
#
# The mutation + the admin audit event are performed by the shared
# Onetime::Operations::Org::Unarchive op (the single implementation). This
# command owns only CLI concerns and never audits. The CLI runs outside the app
# autoloaders, so require the op explicitly.
require 'json'
require 'onetime/operations/org/unarchive'
# Org::Shared / Customers::Shared must exist before the `include`s below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../customers/shared'

module Onetime
  module CLI
    class OrgUnarchiveCommand < Command
      # Customers::Shared -> the CLI_ACTOR sentinel.
      # Org::Shared       -> resolve_org + error_exit (json-aware) + org_label.
      include Customers::Shared
      include Org::Shared

      desc 'Restore an archived organization (dry run unless --run)'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid or objid'

      option :run,
        type: :boolean,
        default: false,
        desc: 'Apply the unarchive (without it, plan only)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, run: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)

        result = Onetime::Operations::Org::Unarchive.new(
          org: organization,
          # Never fabricate a Customer for the shell (ADR-023) — the audit trail
          # records the shared CLI sentinel.
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: !run,
        ).call

        OT.info "[cli-org-unarchive] org=#{result.org_id} status=#{result.status} dry_run=#{result.dry_run}"

        json ? output_json(result) : output_text(result, organization)
      end

      private

      def output_text(result, organization)
        label = org_label(organization)
        error_exit("Unarchive failed: #{result.status}", json: false) unless
          Onetime::Operations::Org::Unarchive::OK_STATUSES.include?(result.status)

        case result.status
        when :not_archived
          puts "#{label} is not archived; nothing to do."
        when :planned
          print_plan(result, label)
          puts 'Dry run only — re-run with --run to apply.'
        else
          puts "Unarchived #{label}"
          puts "  cleared comment: #{result.archived_comment}" unless result.archived_comment.to_s.empty?
          puts "  #{pointer_advisory(result)}" if result.pointer_org_id
        end
      end

      # The plan screen names everything the apply would change, so an operator
      # can catch a wrong ORG before they re-run with --run.
      def print_plan(result, label)
        puts 'DRY RUN — nothing has been written yet'
        puts "Organization:     #{label}"
        puts "Owner:            #{result.owner_id || '(none — owner_id points at no live customer)'}"
        puts "Archived comment: #{result.archived_comment.to_s.empty? ? '(none)' : result.archived_comment}"
        puts pointer_advisory(result) if result.pointer_org_id
        puts
      end

      # Advisory, printed on both passes. Never an exit code.
      def pointer_advisory(result)
        "Owner default workspace: #{result.pointer_org_id}; this organization will not become their default"
      end

      def output_json(result)
        payload = result.to_h.merge(status: result.status.to_s)
        puts JSON.pretty_generate(payload)
        exit 1 unless Onetime::Operations::Org::Unarchive::OK_STATUSES.include?(result.status)
      end
    end

    register 'org unarchive', OrgUnarchiveCommand
  end
end
