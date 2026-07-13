# lib/onetime/cli/memberships/set_role_command.rb
#
# frozen_string_literal: true

# Change an organization member's role.
#
# Usage:
#   bin/ots memberships set-role ORG CUSTOMER admin              # confirm, then set
#   bin/ots memberships set-role ORG user@example.com owner --yes
#   bin/ots memberships set-role ORG ur123abc member --json
#
# The mutation + entitlement re-materialization + admin audit event is performed
# by the shared Onetime::Operations::Memberships::SetRole op (the single
# implementation; the colonel SetMembershipRole Logic class is the other adapter).
# This command owns only CLI concerns. The CLI runs outside the app autoloaders,
# so require the op explicitly.
require 'json'
require 'onetime/operations/memberships/set_role'

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

      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, customer:, role:, yes: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'set role on', json: json)
        role         = role.to_s.strip.downcase

        unless yes
          if json
            error_exit('Refusing to change role without --yes in --json mode', json: true)
          end

          print "Set #{member.obscure_email} to '#{role}' in #{organization.extid}? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Onetime::Operations::Memberships::SetRole.new(
          org: organization,
          customer: member,
          new_role: role,
          actor: Customers::Shared::CLI_ACTOR,
        ).call

        OT.info "[cli-memberships-set-role] org=#{organization.extid} member=#{member.extid} " \
                "status=#{result.status} #{result.from}->#{result.to}"

        json ? output_json(result, member) : output_text(result, member)
      end

      private

      def output_text(result, member)
        case result.status
        when :success
          puts "#{member.obscure_email}: #{result.from} -> #{result.to}"
        when :no_change
          puts "#{member.obscure_email} already has role '#{result.to}'"
        when :invalid_role
          error_exit("Invalid role. Must be one of: #{Onetime::Operations::Memberships::SetRole::VALID_ROLES.join(', ')}", json: false)
        when :not_found
          error_exit("#{member.obscure_email} is not an active member of #{result.org_id}", json: false)
        when :last_owner
          error_exit('Cannot demote the last remaining owner of the organization', json: false)
        end
      end

      def output_json(result, member)
        payload = {
          status: result.status,
          org_id: result.org_id,
          member_id: member.extid,
          email: member.obscure_email,
          from: result.from,
          to: result.to,
        }
        puts JSON.pretty_generate(payload)
        exit 1 unless [:success, :no_change].include?(result.status)
      end
    end

    register 'memberships set-role', MembershipsSetRoleCommand
  end
end
