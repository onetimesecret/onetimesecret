# apps/api/domains/cli/repair_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'onetime/operations/domains/repair'

module Onetime
  module CLI
    # Repair domain
    class DomainsRepairCommand < Command
      include DomainsHelpers

      # Audit actor recorded for CLI-initiated mutations. The shell carries no
      # authenticated colonel identity; a plain, non-secret public sentinel is
      # used — never an internal objid. Mirrors BannedIpsBanCommand::CLI_ACTOR.
      CLI_ACTOR = 'cli'

      desc 'Fix domain relationship issues'

      argument :domain_name, type: :string, required: true, desc: 'Domain name'

      option :org_id,
        type: :string,
        default: nil,
        desc: 'Organization ID to assign if domain is orphaned'

      option :force,
        type: :boolean,
        default: false,
        desc: 'Skip confirmation prompt'

      def call(domain_name:, org_id: nil, force: false, **)
        boot_application!

        domain = load_domain_by_name(domain_name)
        return unless domain

        puts "Checking domain: #{domain_name}"
        puts

        # Resolve the target org for the ORPHANED case silently — the op decides
        # whether it's needed (it's ignored when the domain already has an org_id).
        org = org_id ? load_organization(org_id, silent: true) : nil

        # Dry-run first to compute the plan (issues found) without mutating.
        plan = Onetime::Operations::Domains::Repair.new(
          domain: domain, org: org, actor: CLI_ACTOR, dry_run: true,
        ).call

        case plan.status
        when :needs_org
          puts 'Issue: Domain is orphaned (no org_id)'
          puts 'Fix: Provide --org-id=<id> to assign to an organization'
          return
        when :org_not_found
          puts "Error: Organization '#{domain.org_id}' not found"
          puts "Issue: org_id is #{domain.org_id} but organization not found"
          puts 'Fix: Provide --org-id=<id> to assign to a valid organization'
          return
        when :no_issues
          puts 'No issues found - domain relationships are consistent'
          return
        end

        puts 'Issues Found:'
        plan.issues.each_with_index do |issue, idx|
          puts "  #{idx + 1}. #{issue}"
        end
        puts

        unless force
          print 'Apply repairs? [y/N]: '
          response = $stdin.gets.chomp
          unless response.downcase == 'y'
            puts 'Cancelled'
            return
          end
        end

        # Apply — the op mutates and records exactly one audit event.
        result = Onetime::Operations::Domains::Repair.new(
          domain: domain, org: org, actor: CLI_ACTOR, dry_run: false,
        ).call

        puts 'Applying repairs:'
        result.repairs_applied.each do |repair_result|
          puts "  #{repair_result}"
        end

        OT.info "[CLI] Domain repair: #{domain_name} - #{result.issues.size} issues fixed"
        puts
        puts 'Repair complete'
      end
    end
  end
end

Onetime::CLI.register 'domains repair', Onetime::CLI::DomainsRepairCommand
