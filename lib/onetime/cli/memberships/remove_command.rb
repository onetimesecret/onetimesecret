# lib/onetime/cli/memberships/remove_command.rb
#
# frozen_string_literal: true

# Remove a member from an organization.
#
# Usage:
#   bin/ots memberships remove ORG CUSTOMER              # confirm, then remove
#   bin/ots memberships remove ORG user@example.com --yes
#   bin/ots memberships remove ORG ur123abc --json
#
# The mutation (membership teardown + materialized-entitlement cleanup) + admin
# audit event is performed by the shared Onetime::Operations::Memberships::Remove
# op (the single implementation; the colonel RemoveMembership Logic class is the
# other adapter). This command owns only CLI concerns. The CLI runs outside the
# app autoloaders, so require the op explicitly.
require 'json'
require 'onetime/operations/memberships/remove'

module Onetime
  module CLI
    class MembershipsRemoveCommand < Command
      include Customers::Shared
      include Memberships::Shared

      desc 'Remove a member from an organization (clears their entitlements)'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid'
      argument :customer,
        type: :string,
        required: true,
        desc: 'Member email, extid, or Rodauth account ID'

      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, customer:, yes: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'remove', json: json)

        unless yes
          if json
            error_exit('Refusing to remove member without --yes in --json mode', json: true)
          end

          print "Remove #{member.obscure_email} from #{organization.extid}? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Onetime::Operations::Memberships::Remove.new(
          org: organization,
          customer: member,
          actor: Customers::Shared::CLI_ACTOR,
        ).call

        OT.info "[cli-memberships-remove] org=#{organization.extid} member=#{member.extid} status=#{result.status}"

        json ? output_json(result, member) : output_text(result, member)
      end

      private

      def output_text(result, member)
        case result.status
        when :success
          puts "Removed #{member.obscure_email} from #{result.org_id}"
        when :not_found
          error_exit("#{member.obscure_email} is not a member of #{result.org_id}", json: false)
        when :last_owner
          error_exit('Cannot remove the last remaining owner of the organization', json: false)
        end
      end

      def output_json(result, member)
        payload = {
          status: result.status,
          org_id: result.org_id,
          member_id: member.extid,
          email: member.obscure_email,
          role: result.role,
        }
        puts JSON.pretty_generate(payload)
        exit 1 unless result.status == :success
      end
    end

    register 'memberships remove', MembershipsRemoveCommand
  end
end
