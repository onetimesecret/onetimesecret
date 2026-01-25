# apps/api/domains/cli/repair_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Repair domain
    class DomainsRepairCommand < Command
      include DomainsHelpers

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

        issues_found = []
        repairs      = []

        # Check 1: Orphaned domain
        if domain.org_id.to_s.empty?
          if org_id
            issues_found << 'Domain is orphaned (no org_id)'
            repairs << -> {
              domain.org_id  = org_id
              domain.updated = OT.now.to_i
              domain.save
              org            = load_organization(org_id)
              org.add_domain(domain.domainid) if org
              "Assigned to organization #{org_id}"
            }
          else
            puts 'Issue: Domain is orphaned (no org_id)'
            puts 'Fix: Provide --org-id=<id> to assign to an organization'
            return
          end
        else
          # Check 2: org_id set but not in organization's collection
          org = load_organization(domain.org_id)
          if org
            domains_in_org = org.list_domains
            unless domains_in_org.include?(domain.domainid)
              issues_found << "org_id is #{domain.org_id} but not in organization's domains collection"
              repairs << -> {
                org.add_domain(domain.domainid)
                "Added to organization #{domain.org_id} collection"
              }
            end
          else
            issues_found << "org_id is #{domain.org_id} but organization not found"
            puts "Issue: org_id is #{domain.org_id} but organization not found"
            puts 'Fix: Provide --org-id=<id> to assign to a valid organization'
            return
          end
        end

        if issues_found.empty?
          puts 'No issues found - domain relationships are consistent'
          return
        end

        puts 'Issues Found:'
        issues_found.each_with_index do |issue, idx|
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

        puts 'Applying repairs:'
        repairs.each do |repair|
          result = repair.call
          puts "  #{result}"
        end

        OT.info "[CLI] Domain repair: #{domain_name} - #{issues_found.size} issues fixed"
        puts
        puts 'Repair complete'
      end
    end
  end
end

Onetime::CLI.register 'domains repair', Onetime::CLI::DomainsRepairCommand
