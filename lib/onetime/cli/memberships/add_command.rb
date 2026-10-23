# lib/onetime/cli/memberships/add_command.rb
#
# frozen_string_literal: true

# Add a member to an organization.
#
# Usage:
#   bin/ots memberships add ORG CUSTOMER                    # confirm, add as member
#   bin/ots memberships add ORG user@example.com --role admin --yes
#   bin/ots memberships add ORG ur123abc --json
#   bin/ots memberships add ORG CUSTOMER --default --yes    # ...and make ORG their default
#
# ORG follows Org::Shared#resolve_org (extid, objid, cus_/sub_ Stripe id or
# custom-domain hostname); CUSTOMER follows Customers::Shared#resolve_customer.
#
# --default then makes ORG the customer's default organization (the one
# active when they sign in) once they are an active member of it — after a
# fresh add and when they already were a member — through
# Onetime::Operations::Customers::SetDefaultOrganization, the same op behind
# `bin/ots customers set-default-org`. Declining the confirmation prompt is the
# preview: nothing is written until it is accepted (or --yes is given).
#
# The mutation (add + entitlement materialization) + admin audit event is
# performed by the shared Onetime::Operations::Memberships::Add op (the single
# implementation; the colonel AddMembership Logic class is the other adapter).
# This command owns only CLI concerns. The CLI runs outside the app autoloaders,
# so require the ops explicitly.
require 'json'
require 'onetime/operations/memberships/add'
require 'onetime/operations/customers/set_default_organization'

# Memberships::Shared / Customers::Shared must exist before the `include`s below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../customers/shared'

module Onetime
  module CLI
    class MembershipsAddCommand < Command
      include Customers::Shared
      include Memberships::Shared

      desc 'Add a customer to an organization (materializes entitlements)'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid, objid, cus_/sub_ Stripe id, or custom-domain hostname'
      argument :customer,
        type: :string,
        required: true,
        desc: 'Customer email, extid, objid, or Rodauth account ID'

      option :role,
        type: :string,
        default: 'member',
        desc: "Role for a fresh add: #{Onetime::Operations::Memberships::Add::VALID_ROLES.join(', ')} (default: member)"
      option :default,
        type: :boolean,
        default: false,
        desc: "Also set ORG as the customer's default organization"
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      # Add statuses after which the customer is an active member of ORG, so
      # --default may point at it.
      DEFAULT_ELIGIBLE = [:success, :no_change].freeze

      # SetDefaultOrganization statuses that leave ORG as the default.
      DEFAULT_APPLIED = [:success, :no_change].freeze

      def call(org:, customer:, role: 'member', default: false, yes: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'add', json: json)
        role         = role.to_s.strip.downcase

        if default && organization.archived?
          error_exit("Cannot make archived organization #{organization.extid} a default", json: json)
        end

        unless yes
          if json
            error_exit('Refusing to add member without --yes in --json mode', json: true)
          end

          suffix   = default ? ' and make it their default organization' : ''
          print "Add #{member.obscure_email} to #{organization.extid} as '#{role}'#{suffix}? [y/N] "
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

        default_status = default ? apply_default_org(result, member, organization) : nil

        if json
          output_json(result, member, default_status)
        else
          output_text(result, member, default_status)
        end
      end

      private

      # The default-org write, its eligibility re-check (active membership, not
      # archived) and its audit event all belong to SetDefaultOrganization;
      # this only decides whether to ask.
      #
      # @return [Symbol, nil] the op's status; nil when the add left the
      #   customer outside ORG (invalid role) so nothing was attempted
      def apply_default_org(result, member, organization)
        return nil unless DEFAULT_ELIGIBLE.include?(result.status)

        Onetime::Operations::Customers::SetDefaultOrganization.new(
          customer: member,
          organization: organization,
          actor: Customers::Shared::CLI_ACTOR,
        ).call.status
      end

      def output_text(result, member, default_status)
        case result.status
        when :success
          puts "Added #{member.obscure_email} to #{result.org_id} as '#{result.role}'"
        when :no_change
          puts "#{member.obscure_email} is already a member (role: #{result.role}). " \
               'Use `memberships set-role` to change it.'
        when :invalid_role
          error_exit("Invalid role. Must be one of: #{Onetime::Operations::Memberships::Add::VALID_ROLES.join(', ')}", json: false)
        end

        return if default_status.nil?

        unless DEFAULT_APPLIED.include?(default_status)
          error_exit("Default organization not changed (#{default_status})", json: false)
        end

        puts "Default organization for #{member.obscure_email}: #{result.org_id}"
      end

      def output_json(result, member, default_status)
        payload = {
          status: result.status,
          org_id: result.org_id,
          member_id: member.extid,
          email: member.obscure_email,
          role: result.role,
        }

        # Present only with --default: SetDefaultOrganization's status.
        payload[:default_org_status] = default_status if default_status
        puts JSON.pretty_generate(payload)
        exit 1 if result.status == :invalid_role
        exit 1 if default_status && !DEFAULT_APPLIED.include?(default_status)
      end
    end

    register 'memberships add', MembershipsAddCommand
  end
end
