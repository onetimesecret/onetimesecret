# lib/onetime/cli_v2/domains_command.rb
#
# frozen_string_literal: true

require_relative '../cli/domains_command'

module Onetime
  module CLI
    module V2
      class DomainsCommand < Dry::CLI::Command
        desc 'Domain management tools for custom domains'

        argument :subcommand, type: :string, required: false, desc: 'Subcommand (info, list-orphaned, transfer, repair, bulk-repair)'
        argument :domain, type: :string, required: false, desc: 'Domain name (for info, transfer, repair)'

        option :list, type: :boolean, default: false, aliases: ['l'], desc: 'List domains (default behavior)'
        option :orphaned, type: :boolean, default: false, desc: 'Filter for orphaned domains only'
        option :org_id, type: :string, desc: 'Filter by organization ID'
        option :verified, type: :boolean, default: false, desc: 'Filter for verified domains only'
        option :unverified, type: :boolean, default: false, desc: 'Filter for unverified domains only'
        option :from_org, type: :string, desc: 'Source organization for transfer'
        option :to_org, type: :string, desc: 'Destination organization for transfer'
        option :force, type: :boolean, default: false, aliases: ['f'], desc: 'Skip confirmations'
        option :dry_run, type: :boolean, default: false, desc: 'Preview changes without applying'

        def call(subcommand: nil, domain: nil, list: false, orphaned: false, org_id: nil,
                 verified: false, unverified: false, from_org: nil, to_org: nil,
                 force: false, dry_run: false, **)
          # Boot the application
          OT.boot! :cli

          # Build argv array
          argv = []
          argv << subcommand if subcommand
          argv << domain if domain

          # Create mock drydock interface
          cmd = Onetime::DomainsCommand.new
          cmd.instance_variable_set(:@argv, argv)
          cmd.instance_variable_set(:@option,
            Struct.new(:list, :orphaned, :org_id, :verified, :unverified,
                      :from_org, :to_org, :force, :dry_run).new(
              list, orphaned, org_id, verified, unverified,
              from_org, to_org, force, dry_run
            )
          )

          def cmd.argv; @argv; end
          def cmd.option; @option; end

          cmd.init
          cmd.domains
        end
      end

      # Register the command
      register 'domains', DomainsCommand
    end
  end
end
