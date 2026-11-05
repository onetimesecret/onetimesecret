# lib/onetime/cli/customers/set_default_org_command.rb
#
# frozen_string_literal: true

# Set a customer's default organization.
#
# Usage:
#   bin/ots customers set-default-org CUSTOMER ORG             # dry run (the default)
#   bin/ots customers set-default-org user@example.com on123abc --apply
#   bin/ots customers set-default-org ur123abc on123abc --apply --json
#
# DRY RUN IS THE DEFAULT. Nothing is written without --apply (-y/--yes/-f are
# aliases). There is no confirmation prompt: the bare run is the preview, and
# --dry-run only says so explicitly.
#
# Only an organization the customer is already an active member of, and not an
# archived one, can be chosen. The check, the write and the admin audit event
# are performed by the shared Onetime::Operations::Customers::SetDefaultOrganization
# op (the colonel SetUserDefaultOrganization Logic class is the other adapter).
# This command owns only CLI concerns. The CLI runs outside the app
# autoloaders, so require the op explicitly.
require 'json'
require 'onetime/operations/customers/set_default_organization'

# Customers::Shared / Memberships::Shared must exist before the `include`s
# below. Required here (not only from the lib/onetime/cli.rb manifest) so this
# file cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../memberships/shared'

require_relative '../write_gate'

module Onetime
  module CLI
    class CustomersSetDefaultOrgCommand < Command
      include Customers::Shared
      include Memberships::Shared
      include WriteGate

      desc "Set a customer's default organization (must already be an active member)"

      argument :customer,
        type: :string,
        required: true,
        desc: 'Customer email, extid, objid, or Rodauth account ID'
      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid or objid'

      # OPTIONAL operator-supplied why (#4338), recorded in the audit detail
      # of the event this command's op writes.
      option :reason,
        type: :string,
        default: nil,
        desc: 'Operator-supplied reason (recorded in the admin audit trail)'
      write_gate_options 'Write the change'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(customer:, org:, reason: nil, apply: false, dry_run: false, json: false, **)
        boot_application!

        dry_run      = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        target       = resolve_member(customer, action: 'set the default organization of', json: json)
        organization = resolve_org(org, json: json)

        result = Onetime::Operations::Customers::SetDefaultOrganization.new(
          customer: target,
          organization: organization,
          actor: Customers::Shared::CLI_ACTOR,
          reason: reason,
          dry_run: dry_run,
        ).call

        OT.info "[cli-customers-set-default-org] customer=#{target.extid} org=#{organization.extid} " \
                "status=#{result.status}"

        json ? output_json(result) : output_text(result)
      end

      private

      def output_text(result)
        who      = result.customer.obscure_email
        org      = result.organization.extid
        previous = result.previous&.extid || '(none)'

        case result.status
        when :success
          puts "#{who}: default organization #{previous} -> #{org}"
        when :no_change
          puts "#{who}: #{org} is already the default organization"
        when :dry_run
          dry_run_header
          puts "#{who}: would set default organization #{previous} -> #{org}"
          dry_run_footer('set the default')
        when :not_member
          error_exit("#{who} is not an active member of #{org}", json: false)
        when :archived
          error_exit("#{org} is archived and cannot be a default organization", json: false)
        when :anonymous
          error_exit('Cannot set the default organization of an anonymous customer', json: false)
        end
      end

      def output_json(result)
        payload = {
          status: result.status,
          customer_id: result.customer.extid,
          email: result.customer.obscure_email,
          default_organization: result.organization.extid,
          previous_default_organization: result.previous&.extid,
          dry_run: result.dry_run,
        }
        puts JSON.pretty_generate(payload)
        exit 1 if result.refused?
      end
    end

    register 'customers set-default-org', CustomersSetDefaultOrgCommand
  end
end
