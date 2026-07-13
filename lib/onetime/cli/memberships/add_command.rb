# lib/onetime/cli/memberships/add_command.rb
#
# frozen_string_literal: true

# Add a member to an organization.
#
# Usage:
#   bin/ots memberships add ORG CUSTOMER                    # confirm, add as member
#   bin/ots memberships add ORG user@example.com --role admin --yes
#   bin/ots memberships add ORG ur123abc --json
#
# The mutation (add + entitlement materialization) + admin audit event is
# performed by the shared Onetime::Operations::Memberships::Add op (the single
# implementation; the colonel AddMembership Logic class is the other adapter).
# This command owns only CLI concerns. The CLI runs outside the app autoloaders,
# so require the op explicitly.
require 'json'
require 'onetime/operations/memberships/add'

module Onetime
  module CLI
    class MembershipsAddCommand < Command
      include Customers::Shared

      desc 'Add a customer to an organization (materializes entitlements)'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid'
      argument :customer,
        type: :string,
        required: true,
        desc: 'Customer email, extid, or Rodauth account ID'

      option :role,
        type: :string,
        default: 'member',
        desc: "Role for a fresh add: #{Onetime::Operations::Memberships::Add::VALID_ROLES.join(', ')} (default: member)"
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, customer:, role: 'member', yes: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, json: json)
        role         = role.to_s.strip.downcase

        unless yes
          if json
            error_exit('Refusing to add member without --yes in --json mode', json: true)
          end

          print "Add #{member.obscure_email} to #{organization.extid} as '#{role}'? [y/N] "
          response = $stdin.gets&.strip&.downcase
          unless response == 'y'
            puts 'Aborted.'
            return
          end
        end

        result = Onetime::Operations::Memberships::Add.new(
          org: organization,
          customer: member,
          role: role,
          actor: Customers::Shared::CLI_ACTOR,
        ).call

        OT.info "[cli-memberships-add] org=#{organization.extid} member=#{member.extid} " \
                "status=#{result.status} role=#{result.role}"

        json ? output_json(result, member) : output_text(result, member)
      end

      private

      def output_text(result, member)
        case result.status
        when :success
          puts "Added #{member.obscure_email} to #{result.org_id} as '#{result.role}'"
        when :no_change
          puts "#{member.obscure_email} is already a member (role: #{result.role}). " \
               'Use `memberships set-role` to change it.'
        when :invalid_role
          error_exit("Invalid role. Must be one of: #{Onetime::Operations::Memberships::Add::VALID_ROLES.join(', ')}", json: false)
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
        exit 1 if result.status == :invalid_role
      end

      def resolve_org(identifier, json:)
        organization = Onetime::Organization.find_by_extid(identifier.to_s.strip)
        error_exit("Organization not found: #{identifier}", json: json) unless organization
        organization
      end

      def resolve_member(identifier, json:)
        member = resolve_customer(identifier)
        error_exit("Customer not found: #{identifier}", json: json) unless member
        error_exit('Cannot add anonymous customer', json: json) if member.anonymous?
        member
      end

      def error_exit(message, json:)
        puts(json ? JSON.generate({ error: message }) : "Error: #{message}")
        exit 1
      end
    end

    register 'memberships add', MembershipsAddCommand
  end
end
