# lib/onetime/cli/org/create_command.rb
#
# frozen_string_literal: true

# Create an organization owned by an existing customer.
#
# Usage:
#   bin/ots org create "Acme Inc" --owner user@example.com            # dry run (the default)
#   bin/ots org create "Acme Inc" --owner ur123abc --apply            # create
#   bin/ots org create "Acme Inc" --owner 123 --apply --json          # machine-readable
#   bin/ots org create "Acme Inc" --owner user@example.com --apply \
#     --contact-email billing@acme.test --description "Primary tenant"
#
# OWNER is an email, customer extid, or Rodauth account ID (the shared
# Customers::Shared#resolve_customer contract). The owner MUST already exist —
# this command never fabricates a Customer (ADR-023: real, not synthesized).
#
# DRY RUN IS THE DEFAULT. Nothing is written without --apply (-y/--yes/-f are
# aliases). There is no confirmation prompt: the bare run validates the input
# and reports the org it would create, and --dry-run only says so explicitly.
#
# The mutation + the admin audit event are performed by the shared
# Onetime::Operations::Org::Create op (the single implementation). This command
# owns only CLI concerns. The CLI runs outside the app autoloaders, so require
# the op explicitly.
#
# NOT offered, deliberately (see the op's class comment):
#   --plan          would make a lib/ op depend on the billing app; run
#                   `bin/ots org reconcile ORG --apply` afterwards instead.
#   --set-default   default_org_id is customer-scoped state, not org state.
#   --is-default    is_default: true makes the org UNDELETABLE; signup owns it.
require 'json'
require 'onetime/operations/org/create'
# Org::Shared / Customers::Shared must exist before the `include`s below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../customers/shared'

module Onetime
  module CLI
    class OrgCreateCommand < Command
      # Customers::Shared -> resolve_customer + the CLI_ACTOR sentinel.
      # Org::Shared       -> error_exit (json-aware) + org_label.
      include Customers::Shared
      include Org::Shared

      desc 'Create an organization owned by an existing customer'

      # :planned is the dry run; every other status but :created is a rejection.
      OK_STATUSES = [:created, :planned].freeze

      argument :display_name,
        type: :string,
        required: true,
        desc: 'Organization display name'

      # dry-cli does not enforce `required:` on OPTIONS (only on arguments), so
      # the "required" here is documentation and #resolve_owner is the actual
      # guard. Do not drop either one.
      option :owner,
        type: :string,
        required: true,
        desc: 'REQUIRED. Owner email, customer extid, or Rodauth account ID'
      option :contact_email,
        type: :string,
        desc: 'Billing/contact email (must be globally unique)'
      option :description,
        type: :string,
        desc: 'Organization description'
      option :apply,
        type: :boolean,
        default: false,
        aliases: ['-y', '--yes', '-f'],
        desc: 'Create the organization (default: dry run, nothing written)'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview only (the default; contradicts --apply)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(display_name:, owner: nil, contact_email: nil, description: nil,
               apply: false, dry_run: false, json: false, **)
        boot_application!

        dry_run        = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        owner_customer = resolve_owner(owner, json: json)

        result = Onetime::Operations::Org::Create.new(
          display_name: display_name,
          owner: owner_customer,
          # Never fabricate a Customer for the shell (ADR-023) — the audit trail
          # records the shared CLI sentinel.
          actor: Customers::Shared::CLI_ACTOR,
          contact_email: contact_email,
          description: description,
          dry_run: dry_run,
        ).call

        OT.info "[cli-org-create] status=#{result.status} org=#{result.org_id} " \
                "owner=#{owner_customer.extid} dry_run=#{dry_run}"

        json ? output_json(result, owner_customer, dry_run: dry_run) : output_text(result, owner_customer)
      end

      private

      # Resolve to a real, non-anonymous Customer or exit non-zero. Never
      # returns nil, so the op cannot be handed a fabricated owner.
      def resolve_owner(identifier, json:)
        error_exit('--owner is required', json: json) if identifier.to_s.strip.empty?

        customer = resolve_customer(identifier)
        error_exit("Customer not found: #{identifier}", json: json) unless customer
        error_exit('Cannot create an organization owned by an anonymous customer', json: json) if customer.anonymous?

        customer
      end

      def output_text(result, owner_customer)
        error_exit(result.message, json: false) unless OK_STATUSES.include?(result.status)

        if result.status == :planned
          puts 'DRY RUN — nothing was written'
          puts "Would create '#{result.display_name}' owner=#{owner_customer.obscure_email}"
          puts "contact_email: #{result.contact_email}" if result.contact_email
          puts 'Re-run with --apply to create.'
          return
        end

        puts "#{result.org_id} created: '#{result.display_name}' owner=#{owner_customer.obscure_email}"
        puts "objid: #{result.objid}"
        puts "contact_email: #{result.contact_email}" if result.contact_email
      end

      def output_json(result, owner_customer, dry_run:)
        payload = {
          status: result.status,
          org_id: result.org_id,
          objid: result.objid,
          display_name: result.display_name,
          owner_id: result.owner_id,
          owner_email: owner_customer.obscure_email,
          contact_email: result.contact_email,
          message: result.message,
          dry_run: dry_run,
        }
        puts JSON.pretty_generate(payload)
        exit 1 unless OK_STATUSES.include?(result.status)
      end
    end

    register 'organizations create', OrgCreateCommand
  end
end
