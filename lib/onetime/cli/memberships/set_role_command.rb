# lib/onetime/cli/memberships/set_role_command.rb
#
# frozen_string_literal: true

# Change an organization member's role.
#
# Usage:
#   bin/ots memberships set-role ORG CUSTOMER admin              # dry run (the default)
#   bin/ots memberships set-role ORG user@example.com owner --apply
#   bin/ots memberships set-role ORG ur123abc member --apply --json
#
# DRY RUN IS THE DEFAULT. Nothing is written without --apply (-y/--yes/-f are
# aliases). There is no confirmation prompt: the bare run reports the change
# it would make, and --dry-run only says so explicitly.
#
# The mutation + entitlement re-materialization + admin audit event is performed
# by the shared Onetime::Operations::Memberships::SetRole op (the single
# implementation; the colonel SetMembershipRole Logic class is the other adapter).
# This command owns only CLI concerns. The CLI runs outside the app autoloaders,
# so require the op explicitly.
require 'json'
require 'onetime/operations/memberships/set_role'

# Memberships::Shared / Customers::Shared must exist before the `include`s below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../customers/shared'

module Onetime
  module CLI
    class MembershipsSetRoleCommand < Command
      include Customers::Shared
      include Memberships::Shared

      desc "Set an organization member's role (re-materializes entitlements)"

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid'
      argument :customer,
        type: :string,
        required: true,
        desc: 'Member email, extid, or Rodauth account ID'
      argument :role,
        type: :string,
        required: true,
        desc: "Target role: #{Onetime::Operations::Memberships::SetRole::VALID_ROLES.join(', ')}"

      # OPTIONAL operator-supplied why (#4338), recorded in the audit detail
      # of the event this command's op writes. Same flag, same wording and same
      # blank-means-absent handling as every other destructive CLI verb.
      option :reason,
        type: :string,
        default: nil,
        desc: 'Operator-supplied reason (recorded in the admin audit trail)'
      option :apply,
        type: :boolean,
        default: false,
        aliases: ['-y', '--yes', '-f'],
        desc: 'Change the role (default: dry run, nothing written)'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview only (the default; contradicts --apply)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      # Statuses that exit 0.
      OK_STATUSES = [:success, :no_change, :dry_run].freeze

      def call(org:, customer:, role:, reason: nil, apply: false, dry_run: false, json: false, **)
        boot_application!

        dry_run      = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'set role on', json: json)
        role         = role.to_s.strip.downcase

        result = Onetime::Operations::Memberships::SetRole.new(
          org: organization,
          customer: member,
          new_role: role,
          actor: Customers::Shared::CLI_ACTOR,
          reason: reason,
          dry_run: dry_run,
        ).call

        OT.info "[cli-memberships-set-role] org=#{organization.extid} member=#{member.extid} " \
                "status=#{result.status} #{result.from}->#{result.to} dry_run=#{dry_run}"

        json ? output_json(result, member, dry_run: dry_run) : output_text(result, member, dry_run: dry_run)
      end

      private

      def output_text(result, member, dry_run:)
        case result.status
        when :success
          puts "#{member.obscure_email}: #{result.from} -> #{result.to}"
        when :dry_run
          puts "Would change #{member.obscure_email}: #{result.from} -> #{result.to}"
          puts 'Dry run - nothing written. Re-run with --apply to write.'
        when :no_change
          puts "#{member.obscure_email} already has role '#{result.to}'"
          puts 'Dry run - nothing to write.' if dry_run
        when :invalid_role
          error_exit("Invalid role. Must be one of: #{Onetime::Operations::Memberships::SetRole::VALID_ROLES.join(', ')}", json: false)
        when :not_found
          error_exit("#{member.obscure_email} is not an active member of #{result.org_id}", json: false)
        when :last_owner
          error_exit('Cannot demote the last remaining owner of the organization', json: false)
        end
      end

      def output_json(result, member, dry_run:)
        payload = {
          status: result.status,
          org_id: result.org_id,
          member_id: member.extid,
          email: member.obscure_email,
          from: result.from,
          to: result.to,
          dry_run: dry_run,
        }
        puts JSON.pretty_generate(payload)
        exit 1 unless OK_STATUSES.include?(result.status)
      end
    end

    register 'memberships set-role', MembershipsSetRoleCommand
  end
end
