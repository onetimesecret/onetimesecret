# lib/onetime/cli/org/unarchive_command.rb
#
# frozen_string_literal: true

# Restore an archived organization.
#
# Usage:
#   bin/ots org unarchive ORG                   # dry run (the default): show what would be cleared
#   bin/ots org unarchive ORG --run             # apply
#   bin/ots org unarchive ORG --run --force     # apply even when the owner's default points elsewhere
#   bin/ots org unarchive ORG --run --json      # machine-readable
#
# ORG is an org extid or objid (Onetime::CLI::Org::Shared#resolve_org).
#
# Unlike `org delete` / `org transfer-ownership` there is no confirmation
# prompt: the default IS the dry run, and --run is the explicit apply (the
# `bin/ots migrations …` convention). The op is constructed exactly once per
# invocation.
#
# ## Guardrails
#
#   not_archived              the org is live; exit 0, nothing written.
#   default_pointer_elsewhere the owner's default_org_id names a different live
#                             organization: restoring this one changes nothing
#                             about where the owner lands. Exit 1 so the operator
#                             decides about the pointer deliberately; override
#                             with --force. The #4717 plan drops this refusal to
#                             an advisory field in PR 2.
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
      option :force,
        type: :boolean,
        default: false,
        desc: "Unarchive even when the owner's default_org_id names another live organization"
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, run: false, force: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)

        result = Onetime::Operations::Org::Unarchive.new(
          org: organization,
          # Never fabricate a Customer for the shell (ADR-023) — the audit trail
          # records the shared CLI sentinel.
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: !run,
          force: force,
        ).call

        OT.info "[cli-org-unarchive] org=#{result.org_id} status=#{result.status} " \
                "dry_run=#{result.dry_run} force=#{result.force}"

        json ? output_json(result) : output_text(result, organization)
      end

      private

      def output_text(result, organization)
        label = org_label(organization)
        refuse(result, label) unless Onetime::Operations::Org::Unarchive::OK_STATUSES.include?(result.status)

        case result.status
        when :not_archived
          puts "#{label} is not archived; nothing to do."
        when :planned
          print_plan(result, label)
          puts 'Dry run only — re-run with --run to apply.'
        else
          puts "Unarchived #{label}"
          puts "  cleared comment: #{result.archived_comment}" unless result.archived_comment.to_s.empty?
          return unless result.pointer_org_id

          puts "  NOTE: the owner's default_org_id names #{result.pointer_org_id} (--force in effect). " \
               'Repoint it if this organization should be their default.'
        end
      end

      # The plan screen names everything the apply would change and the state
      # that decides whether the repair holds, so an operator can catch a
      # wrong ORG before they re-run with --run.
      def print_plan(result, label)
        puts 'DRY RUN — nothing has been written yet'
        puts "Organization:     #{label}"
        puts "Owner:            #{result.owner_id || '(none — owner_id points at no live customer)'}"
        puts "Archived comment: #{result.archived_comment.to_s.empty? ? '(none)' : result.archived_comment}"
        puts "Owner default:    #{pointer_line(result)}"
        puts
      end

      def pointer_line(result)
        return 'this organization, empty, or no live organization' unless result.pointer_org_id

        "#{result.pointer_org_id} (another live organization — --force in effect)"
      end

      def output_json(result)
        payload = result.to_h.merge(status: result.status.to_s)
        puts JSON.pretty_generate(payload)
        exit 1 unless Onetime::Operations::Org::Unarchive::OK_STATUSES.include?(result.status)
      end

      # Refusal statuses render the SAME operator guidance on the plan pass and
      # the applied pass, so a --run and a plan-only run cannot drift.
      def refuse(result, label)
        case result.status
        when :default_pointer_elsewhere
          error_exit(
            "#{label}: the owner's default_org_id names another live organization " \
            "(#{result.pointer_org_id}), so restoring this one will not change where they land. " \
            "Repoint the owner's default first, or re-run with --force to unarchive anyway",
            json: false,
          )
        else
          error_exit("Unarchive failed: #{result.status}", json: false)
        end
      end
    end

    register 'org unarchive', OrgUnarchiveCommand
  end
end
