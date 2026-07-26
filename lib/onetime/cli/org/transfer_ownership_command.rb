# lib/onetime/cli/org/transfer_ownership_command.rb
#
# frozen_string_literal: true

# Transfer an organization's ownership to an existing active member.
#
# Usage:
#   bin/ots org transfer-ownership ORG NEW_OWNER                  # plan, confirm, apply
#   bin/ots org transfer-ownership ORG user@example.com --yes     # skip the prompt
#   bin/ots org transfer-ownership ORG ur123abc --yes --json      # machine-readable
#   bin/ots org transfer-ownership ORG ur123abc --demote-to member
#
# ORG is an org extid or objid (Onetime::CLI::Org::Shared#resolve_org).
# NEW_OWNER is an email, customer extid, or Rodauth account ID
# (Customers::Shared#resolve_customer) and MUST ALREADY BE AN ACTIVE MEMBER —
# run `bin/ots memberships add ORG CUSTOMER` first if they are not. This command
# never fabricates a Customer (ADR-023: real, not synthesized).
#
# Without --yes the command runs a DRY RUN first and prints the plan (who loses
# ownership, how many owner memberships get demoted, and to what) before asking
# to confirm. Answering `n` is therefore also how you preview a transfer.
#
# ## If this command is interrupted
#
# The op promotes the new owner BEFORE demoting the old one — it has no choice,
# the sole-owner guard refuses every other ordering. So there is a brief window
# where the org has two `role: 'owner'` memberships and `bin/ots org doctor`
# reports check 4 (`membership_role_sync`) as a WARNING.
#
# RECOVERY IS TO RE-RUN THIS COMMAND, NOT THE DOCTOR. A re-run is idempotent and
# demotes every other owner. `org doctor` marks check 4 `repairable: false` and
# will not fix it for you.
#
# The mutation + the admin audit event are performed by the shared
# Onetime::Operations::Org::TransferOwnership op (the single implementation; a
# colonel endpoint is filed separately, D33). This command owns only CLI
# concerns. The CLI runs outside the app autoloaders, so require the op
# explicitly.
require 'json'
require 'onetime/operations/org/transfer_ownership'
# Org::Shared / Customers::Shared must exist before the `include`s below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative 'shared'
require_relative '../customers/shared'

module Onetime
  module CLI
    class OrgTransferOwnershipCommand < Command
      # Customers::Shared -> resolve_customer + the CLI_ACTOR sentinel.
      # Org::Shared       -> resolve_org + error_exit (json-aware) + org_label.
      include Customers::Shared
      include Org::Shared

      desc 'Transfer an organization to a different existing member'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid or objid'
      argument :new_owner,
        type: :string,
        required: true,
        desc: 'New owner email, extid, or Rodauth account ID (must already be a member)'

      option :demote_to,
        type: :string,
        default: 'admin',
        desc: "Role for the outgoing owner: #{Onetime::Operations::Org::TransferOwnership::DEMOTABLE_ROLES.join(', ')}"
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, new_owner:, demote_to: 'admin', yes: false, json: false, **)
        boot_application!

        organization   = resolve_org(org, json: json)
        # Resolve the incoming owner BEFORE anything else: an operator should
        # learn the identifier is wrong without first confirming a transfer that
        # cannot run.
        owner_customer = resolve_new_owner(new_owner, json: json)
        demote_to      = demote_to.to_s.strip.downcase

        return unless confirm!(organization, owner_customer, demote_to, yes: yes, json: json)

        result = transfer(organization, owner_customer, demote_to, dry_run: false)

        OT.info "[cli-org-transfer-ownership] org=#{organization.extid} to=#{owner_customer.extid} " \
                "status=#{result.status} demoted=#{result.demoted.size}"

        json ? output_json(result, owner_customer) : output_text(result, owner_customer)
      end

      private

      def transfer(organization, owner_customer, demote_to, dry_run:)
        Onetime::Operations::Org::TransferOwnership.new(
          org: organization,
          new_owner: owner_customer,
          # Never fabricate a Customer for the shell (ADR-023) — the audit trail
          # records the shared CLI sentinel.
          actor: Customers::Shared::CLI_ACTOR,
          demote_to: demote_to,
          dry_run: dry_run,
        ).call
      end

      # Resolve to a real, non-anonymous Customer or exit non-zero. Never
      # returns nil, so the op cannot be handed a fabricated owner.
      def resolve_new_owner(identifier, json:)
        customer = resolve_customer(identifier)
        error_exit("Customer not found: #{identifier}", json: json) unless customer
        error_exit('Cannot transfer an organization to an anonymous customer', json: json) if customer.anonymous?

        customer
      end

      # @return [Boolean] true to proceed with the applied run
      def confirm!(organization, owner_customer, demote_to, yes:, json:)
        return true if yes

        # Never mutate production org state from a scripted invocation that did
        # not say so.
        error_exit('Refusing to transfer ownership without --yes in --json mode', json: true) if json

        # The whole point of dry_run defaulting to true: show the operator what
        # this will do — including HOW MANY owner memberships get demoted (D29)
        # — before they answer.
        plan = transfer(organization, owner_customer, demote_to, dry_run: true)
        return false unless print_plan(plan, organization, owner_customer)

        print "Transfer #{org_label(organization)} to #{owner_customer.obscure_email}? [y/N] "
        response = $stdin.gets&.strip&.downcase
        return true if response == 'y'

        puts 'Aborted.'
        false
      end

      # @return [Boolean] true when the plan is worth prompting about. Refusals
      #   exit non-zero here; :no_change reports and returns 0 without a prompt.
      def print_plan(plan, organization, owner_customer)
        refuse(plan, organization, owner_customer) unless
          Onetime::Operations::Org::TransferOwnership::OK_STATUSES.include?(plan.status)

        if plan.status == :no_change
          puts "#{owner_customer.obscure_email} is already the sole owner of #{plan.org_id}"
          return false
        end

        puts 'DRY RUN — nothing has been written yet'
        puts "Organization:  #{org_label(organization)}"
        puts "Current owner: #{plan.from_owner_id || '(none — owner_id points at no live customer)'}"
        puts "New owner:     #{owner_customer.extid} (#{owner_customer.obscure_email})"
        puts "Demote to:     #{plan.from_owner_role_after}"
        puts "Would demote:  #{plan.demoted.size} owner membership(s)#{demoted_list(plan)}"
        puts
        true
      end

      def output_text(result, owner_customer)
        refuse(result, nil, owner_customer) unless
          Onetime::Operations::Org::TransferOwnership::OK_STATUSES.include?(result.status)

        if result.status == :no_change
          puts "#{owner_customer.obscure_email} is already the sole owner of #{result.org_id}"
          return
        end

        puts "#{result.org_id}: owner #{result.from_owner_id || '(none)'} -> " \
             "#{result.to_owner_id} (#{owner_customer.obscure_email})"
        puts "Demoted #{result.demoted.size} previous owner(s) to " \
             "'#{result.from_owner_role_after}'#{demoted_list(result)}"
        return unless result.orphaned_owner

        puts 'NOTE: the previous owner_id pointed at no live customer (org doctor check 1); it has been repaired.'
      end

      # ": ur_a, ur_b" — or nothing at all when there is no one to name.
      def demoted_list(result)
        return '' if result.demoted.empty?

        ": #{result.demoted.join(', ')}"
      end

      def output_json(result, owner_customer)
        payload = {
          status: result.status,
          org_id: result.org_id,
          from_owner_id: result.from_owner_id,
          to_owner_id: result.to_owner_id,
          new_owner_email: owner_customer.obscure_email,
          demoted: result.demoted,
          demoted_to: result.from_owner_role_after,
          orphaned_owner: result.orphaned_owner,
          dry_run: result.dry_run,
        }
        puts JSON.pretty_generate(payload)
        exit 1 unless Onetime::Operations::Org::TransferOwnership::OK_STATUSES.include?(result.status)
      end

      # Refusal statuses render the SAME operator guidance on both the plan pass
      # and the applied pass, so a --yes run and an interactive run cannot drift.
      def refuse(result, organization, owner_customer)
        org_ref = organization ? org_label(organization) : result.org_id

        case result.status
        when :not_member
          error_exit(
            "#{owner_customer.obscure_email} is not an active member of #{org_ref}. " \
            'Run: bin/ots memberships add ORG CUSTOMER first',
            json: false,
          )
        when :invalid_role
          error_exit(
            '--demote-to must be one of: ' \
            "#{Onetime::Operations::Org::TransferOwnership::DEMOTABLE_ROLES.join(', ')}",
            json: false,
          )
        else
          error_exit("Transfer failed: #{result.status}", json: false)
        end
      end
    end

    register 'org transfer-ownership', OrgTransferOwnershipCommand
  end
end
