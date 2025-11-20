# apps/api/domains/cli/transfer_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Transfer domain
    class DomainsTransferCommand < Command
      include DomainsHelpers

      desc 'Transfer domain between organizations'

      argument :domain_name, type: :string, required: true, desc: 'Domain name'

      option :to_org, type: :string, required: true,
        desc: 'Destination organization ID'

      option :from_org, type: :string, default: nil,
        desc: 'Source organization ID (optional, uses domain\'s current org_id)'

      option :force, type: :boolean, default: false,
        desc: 'Skip confirmation prompt'

      def call(domain_name:, to_org:, from_org: nil, force: false, **)
        boot_application!

        domain = load_domain_by_name(domain_name)
        return unless domain

        from_org_id = from_org || domain.org_id

        # Load organizations
        to_org_obj = load_organization(to_org)
        return unless to_org_obj

        from_org_obj = nil
        if from_org_id.to_s.empty?
          puts 'Note: Domain is currently orphaned (no organization)'
        else
          from_org_obj = load_organization(from_org_id)
          return unless from_org_obj

          # Verify current ownership
          unless domain.org_id.to_s == from_org_id.to_s
            puts "Error: Domain org_id (#{domain.org_id}) does not match --from-org (#{from_org_id})"
            return
          end
        end

        # Display transfer details
        puts 'Transfer Details:'
        puts "  Domain:               #{domain_name}"
        if from_org_obj
          puts "  From Organization:    #{from_org_obj.display_name || 'N/A'} (#{from_org_obj.org_id})"
        else
          puts '  From Organization:    ORPHANED'
        end
        puts "  To Organization:      #{to_org_obj.display_name || 'N/A'} (#{to_org_obj.org_id})"
        puts

        unless force
          print 'Confirm transfer? [y/N]: '
          response = $stdin.gets.chomp
          unless response.downcase == 'y'
            puts 'Cancelled'
            return
          end
        end

        # Perform transfer
        begin
          # Remove from old organization's collection if exists
          if from_org_obj
            from_org_obj.remove_domain(domain.domainid)
            puts "  Removed from #{from_org_obj.display_name || from_org_obj.org_id}"
          end

          # TODO: Make this atomic - add_domain should handle both org_id update and collection add
          # Update domain's org_id
          domain.org_id  = to_org
          domain.updated = OT.now.to_i
          domain.save

          # Add to new organization's collection
          begin
            to_org_obj.add_domain(domain.domainid)
            puts "  Added to #{to_org_obj.display_name || to_org_obj.org_id}"
            puts '  Updated org_id field'
          rescue StandardError => ex
            # Rollback: restore original org_id if collection add fails
            domain.org_id = from_org_id
            domain.save
            raise "Failed to add domain to organization collection: #{ex.message}"
          end

          OT.info "[CLI] Domain transfer: #{domain_name} from #{from_org_id || 'orphaned'} to #{to_org}"
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
