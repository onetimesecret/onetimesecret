# lib/onetime/cli_v2/revalidate_domains_command.rb
#
# frozen_string_literal: true

require_relative '../cli/domains_command'

module Onetime
  module CLI
    module V2
      class RevalidateDomainsCommand < Dry::CLI::Command
        desc 'Revalidate domain verification status'

        option :domain, type: :string, aliases: ['d'], desc: 'Domain to revalidate'
        option :custid, type: :string, aliases: ['c'], desc: 'Customer ID to revalidate'

        def call(domain: nil, custid: nil, **)
          # Boot the application
          OT.boot! :cli

          # Create mock drydock interface
          cmd = Onetime::DomainsCommand.new
          cmd.instance_variable_set(:@argv, [])
          cmd.instance_variable_set(:@option, Struct.new(:domain, :custid).new(domain, custid))

          def cmd.argv; @argv; end
          def cmd.option; @option; end

          cmd.init
          cmd.revalidate_domains
        end
      end

      # Register the command
      register 'revalidate-domains', RevalidateDomainsCommand
    end
  end
end
