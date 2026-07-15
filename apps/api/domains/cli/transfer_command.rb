# apps/api/domains/cli/transfer_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'onetime/operations/domains/transfer'

module Onetime
  module CLI
    # Transfer domain
    class DomainsTransferCommand < Command
      include DomainsHelpers

      # Audit actor recorded for CLI-initiated mutations (see repair command).
      CLI_ACTOR = 'cli'

      desc 'Transfer domain between organizations'

      argument :domain_name, type: :string, required: true, desc: 'Domain name'

      option :to_org,
        type: :string,
        required: true,
        desc: 'Destination organization ID'

      option :from_org,
        type: :string,
        default: nil,
        desc: 'Source organization ID (optional, uses domain\'s current org_id)'

      option :force,
        type: :boolean,
        default: false,
        desc: 'Skip confirmation prompt'

      def call(domain_name:, to_org:, from_org: nil, force: false, **)
        boot_application!

        domain = load_domain_by_name(domain_name)
        return unless domain

        # Resolve the destination (required) and, when explicitly given, the source
        # org for the ownership assertion. load_organization prints + returns nil on
        # a miss, preserving the CLI's error output.
        to_org_obj = load_organization(to_org)
        return unless to_org_obj

        from_org_obj = nil
        if from_org
          from_org_obj = load_organization(from_org)
          return unless from_org_obj
        end

        # Dry-run to compute the transfer plan (from/to details, ownership check).
        plan = Onetime::Operations::Domains::Transfer.new(
          domain: domain,
          to_org: to_org_obj,
          from_org: from_org_obj,
          actor: CLI_ACTOR,
          dry_run: true,
        ).call

        if plan.status == :mismatch
          puts "Error: Domain org_id (#{domain.org_id}) does not match --from-org (#{from_org})"
          return
        end

        # Display transfer details from the plan.
        puts 'Note: Domain is currently orphaned (no organization)' if domain.org_id.to_s.empty?

        puts 'Transfer Details:'
        puts "  Domain:               #{domain_name}"
        if plan.from_org_id.to_s.empty?
          puts '  From Organization:    ORPHANED'
        else
          puts "  From Organization:    #{plan.from_org_name || 'N/A'} (#{plan.from_org_id})"
        end
        puts "  To Organization:      #{plan.to_org_name || 'N/A'} (#{plan.to_org_id})"
        puts

        unless force
          print 'Confirm transfer? [y/N]: '
          response = $stdin.gets.chomp
          unless response.downcase == 'y'
            puts 'Cancelled'
            return
          end
        end

        # Perform the transfer — the op mutates + records exactly one audit event.
        begin
          result = Onetime::Operations::Domains::Transfer.new(
            domain: domain,
            to_org: to_org_obj,
            from_org: from_org_obj,
            actor: CLI_ACTOR,
            dry_run: false,
          ).call

          unless result.from_org_id.to_s.empty?
            puts "  Removed from #{result.from_org_name || result.from_org_id}"
          end
          puts "  Added to #{result.to_org_name || result.to_org_id}"
          puts '  Updated org_id field'

          OT.info "[CLI] Domain transfer: #{domain_name} from #{result.from_org_id.to_s.empty? ? 'orphaned' : result.from_org_id} to #{to_org}"
          puts
          puts 'Transfer complete'
        rescue StandardError => ex
          puts "Error during transfer: #{ex.message}"
          OT.le "[CLI] Domain transfer failed: #{ex.message}"
        end
      end
    end
  end
end

Onetime::CLI.register 'domains transfer', Onetime::CLI::DomainsTransferCommand
