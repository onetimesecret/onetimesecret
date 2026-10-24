# lib/onetime/cli/memberships/add_command.rb
#
# frozen_string_literal: true

# Add a member to an organization.
#
# Usage:
#   bin/ots memberships add ORG CUSTOMER                    # dry run (the default): what would change
#   bin/ots memberships add ORG CUSTOMER --apply            # add as member
#   bin/ots memberships add ORG user@example.com --role admin --apply
#   bin/ots memberships add ORG ur123abc --apply --json
#   bin/ots memberships add ORG CUSTOMER --default --apply  # ...and make ORG their default
#
# ORG follows Org::Shared#resolve_org (extid, objid, cus_/sub_ Stripe id or
# custom-domain hostname); CUSTOMER follows Customers::Shared#resolve_customer.
#
# DRY RUN IS THE DEFAULT. Nothing is written without --apply (-y/--yes/-f are
# aliases). There is no confirmation prompt: the bare run is the preview, and
# --dry-run only says so explicitly.
#
# --default then makes ORG the customer's default organization (the one
# active when they sign in) once they are an active member of it — after a
# fresh add and when they already were a member — through
# Onetime::Operations::Customers::SetDefaultOrganization, the same op behind
# `bin/ots customers set-default-org`.
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
      option :apply,
        type: :boolean,
        default: false,
        aliases: ['-y', '--yes', '-f'],
        desc: 'Write the membership (default: dry run, nothing written)'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview only (the default; contradicts --apply)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      # Add statuses after which the customer is an active member of ORG, so
      # --default may point at it.
      DEFAULT_ELIGIBLE = [:success, :no_change].freeze

      # SetDefaultOrganization statuses that leave (or, in a dry run, would
      # leave) ORG as the default.
      DEFAULT_APPLIED = [:success, :no_change, :dry_run].freeze

      def call(org:, customer:, role: 'member', default: false, apply: false, dry_run: false, json: false, **)
        boot_application!

        dry_run      = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'add', json: json)
        role         = role.to_s.strip.downcase

        if default && organization.archived?
          error_exit("Cannot make archived organization #{organization.extid} a default", json: json)
        end

        result = Onetime::Operations::Memberships::Add.new(
          org: organization,
          customer: member,
          role: role,
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: dry_run,
        ).call

        OT.info "[cli-memberships-add] org=#{organization.extid} member=#{member.extid} " \
                "status=#{result.status} role=#{result.role} dry_run=#{dry_run}"

        default_status = default ? apply_default_org(result, member, organization, dry_run: dry_run) : nil

        if json
          output_json(result, member, default_status, dry_run: dry_run)
        else
          output_text(result, member, default_status, dry_run: dry_run)
        end
      end

      private

      # The default-org write, its eligibility re-check (active membership, not
      # archived) and its audit event all belong to SetDefaultOrganization;
      # this only decides whether to ask.
      #
      # A previewed fresh add (:dry_run) made nobody a member yet, so the op's
      # own dry run could only answer :not_member. After the add they would be
      # an active member of an unarchived ORG (checked in #call), which is all
      # the op asks, so the preview reports :dry_run without asking it.
      #
      # @return [Symbol, nil] the op's status; nil when the add left the
      #   customer outside ORG (invalid role) so nothing was attempted
      def apply_default_org(result, member, organization, dry_run:)
        return :dry_run if result.status == :dry_run
        return nil unless DEFAULT_ELIGIBLE.include?(result.status)

        Onetime::Operations::Customers::SetDefaultOrganization.new(
          customer: member,
          organization: organization,
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: dry_run,
        ).call.status
      end

      def output_text(result, member, default_status, dry_run:)
        case result.status
        when :success
          puts "Added #{member.obscure_email} to #{result.org_id} as '#{result.role}'"
        when :dry_run
          puts "Would add #{member.obscure_email} to #{result.org_id} as '#{result.role}'"
        when :no_change
          puts "#{member.obscure_email} is already a member (role: #{result.role}). " \
               'Use `memberships set-role` to change it.'
        when :invalid_role
          error_exit("Invalid role. Must be one of: #{Onetime::Operations::Memberships::Add::VALID_ROLES.join(', ')}", json: false)
        end

        print_default_org(result, member, default_status) unless default_status.nil?
        return unless dry_run

        if result.status == :dry_run || default_status == :dry_run
          puts 'Dry run - nothing written. Re-run with --apply to write.'
        else
          puts 'Dry run - nothing to write.'
        end
      end

      def print_default_org(result, member, default_status)
        unless DEFAULT_APPLIED.include?(default_status)
          error_exit("Default organization not changed (#{default_status})", json: false)
        end

        if default_status == :dry_run
          puts "Would make #{result.org_id} the default organization for #{member.obscure_email}"
        else
          puts "Default organization for #{member.obscure_email}: #{result.org_id}"
        end
      end

      def output_json(result, member, default_status, dry_run:)
        payload = {
          status: result.status,
          org_id: result.org_id,
          member_id: member.extid,
          email: member.obscure_email,
          role: result.role,
          dry_run: dry_run,
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
