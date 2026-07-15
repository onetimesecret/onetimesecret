# apps/api/domains/cli/remove_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'onetime/operations/domains/remove'

module Onetime
  module CLI
    # Remove (permanently delete) a custom domain
    class DomainsRemoveCommand < Command
      include DomainsHelpers

      # Audit actor recorded for CLI-initiated mutations (see transfer command).
      CLI_ACTOR = 'cli'

      desc 'Remove (permanently delete) a custom domain'

      argument :domain_name, type: :string, required: true, desc: 'Domain name, extid, or ID'

      option :force,
        type: :boolean,
        default: false,
        desc: 'Skip confirmation prompt'

      def call(domain_name:, force: false, **)
        boot_application!

        domain = load_domain(domain_name)
        return unless domain

        # Dry-run to compute the removal plan (org details, survivor re-assertion).
        plan = Onetime::Operations::Domains::Remove.new(
          domain: domain,
          actor: CLI_ACTOR,
          dry_run: true,
        ).call

        # Display removal details from the plan.
        puts 'Removal Details:'
        puts "  Domain:               #{plan.display_domain}"
        if plan.org_id.to_s.empty?
          puts '  Organization:         ORPHANED'
        else
          puts "  Organization:         #{plan.org_name || 'N/A'} (#{plan.org_id})"
        end
        if plan.reasserts_survivor
          puts '  Note:                 removing a shadow record; the canonical'
          puts '                        display_domain index entry will survive'
        end
        puts

        unless force
          print 'Permanently remove this domain? [y/N]: '
          # gets returns nil at EOF (closed stdin / piped / CI) — treat as decline.
          response = $stdin.gets&.chomp
          unless response&.downcase == 'y'
            puts 'Cancelled'
            return
          end
        end

        # Perform the removal — the op mutates + records exactly one audit event.
        begin
          result = Onetime::Operations::Domains::Remove.new(
            domain: domain,
            actor: CLI_ACTOR,
            dry_run: false,
          ).call

          puts "  Removed #{result.display_domain}"

          OT.info "[CLI] Domain remove: #{result.display_domain} (#{result.extid})"
          puts
          puts 'Removal complete'
        rescue StandardError => ex
          puts "Error during removal: #{ex.message}"
          OT.le "[CLI] Domain remove failed: #{ex.message}"
        end
      end
    end
  end
end

Onetime::CLI.register 'domains remove', Onetime::CLI::DomainsRemoveCommand
