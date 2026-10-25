# lib/onetime/cli/memberships/remove_command.rb
#
# frozen_string_literal: true

# Remove a member from an organization.
#
# Usage:
#   bin/ots memberships remove ORG CUSTOMER              # dry run (the default)
#   bin/ots memberships remove ORG user@example.com --apply
#   bin/ots memberships remove ORG ur123abc --apply --json
#
# DRY RUN IS THE DEFAULT. Nothing is written without --apply (-y/--yes/-f are
# aliases). There is no confirmation prompt: the bare run reports what would
# be removed, and --dry-run only says so explicitly.
#
# The mutation (membership teardown + materialized-entitlement cleanup) + admin
# audit event is performed by the shared Onetime::Operations::Memberships::Remove
# op (the single implementation; the colonel RemoveMembership Logic class is the
# other adapter). This command owns only CLI concerns. The CLI runs outside the
# app autoloaders, so require the op explicitly.
#
# DEFAULT ORG CLEANUP: an apply reports a member default_org_id that may
# still name the org (Remove::Result#default_org_cleanup == :failed). The
# removal stands, but it exits 1; `customers doctor MEMBER --repair` clears
# the pointer.
require 'json'
require 'onetime/operations/memberships/remove'

# Memberships::Shared / Customers::Shared must exist before the `include`s below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../customers/shared'

require_relative '../write_gate'

module Onetime
  module CLI
    class MembershipsRemoveCommand < Command
      include Customers::Shared
      include Memberships::Shared
      include WriteGate

      desc 'Remove a member from an organization (clears their entitlements)'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid'
      argument :customer,
        type: :string,
        required: true,
        desc: 'Member email, extid, or Rodauth account ID'

      # OPTIONAL operator-supplied why (#4338), recorded in the audit detail
      # of the event this command's op writes. Same flag, same wording and same
      # blank-means-absent handling as every other destructive CLI verb.
      option :reason,
        type: :string,
        default: nil,
        desc: 'Operator-supplied reason (recorded in the admin audit trail)'
      write_gate_options 'Remove the member'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      # Statuses that exit 0.
      OK_STATUSES = [:success, :dry_run].freeze

      def call(org:, customer:, reason: nil, apply: false, dry_run: false, json: false, **)
        boot_application!

        dry_run      = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'remove', json: json)

        result = Onetime::Operations::Memberships::Remove.new(
          org: organization,
          customer: member,
          actor: Customers::Shared::CLI_ACTOR,
          reason: reason,
          dry_run: dry_run,
        ).call

        OT.info "[cli-memberships-remove] org=#{organization.extid} member=#{member.extid} " \
                "status=#{result.status} dry_run=#{dry_run} default_org_cleanup=#{result.default_org_cleanup}"

        json ? output_json(result, member, dry_run: dry_run) : output_text(result, member)
      end

      private

      def output_text(result, member)
        case result.status
        when :success
          puts "Removed #{member.obscure_email} from #{result.org_id}"
          if default_org_cleanup_failed?(result)
            puts "Removal incomplete: the member's default organization may still be #{result.org_id}."
            puts "  Run `bin/ots customers doctor #{member.extid} --repair` to clear it."
            exit 1
          end
        when :dry_run
          dry_run_header
          puts "Would remove #{member.obscure_email} (role: #{result.role}) from #{result.org_id}"
          dry_run_footer('remove')
        when :not_found
          error_exit("#{member.obscure_email} is not a member of #{result.org_id}", json: false)
        when :last_owner
          error_exit('Cannot remove the last remaining owner of the organization', json: false)
        end
      end

      def output_json(result, member, dry_run:)
        payload = {
          status: result.status,
          org_id: result.org_id,
          member_id: member.extid,
          email: member.obscure_email,
          role: result.role,
          dry_run: dry_run,
          default_org_cleanup: result.default_org_cleanup,
        }
        puts JSON.pretty_generate(payload)
        exit 1 unless OK_STATUSES.include?(result.status)
        exit 1 if default_org_cleanup_failed?(result)
      end

      def default_org_cleanup_failed?(result)
        result.default_org_cleanup == :failed
      end
    end

    register 'memberships remove', MembershipsRemoveCommand
  end
end
