# apps/api/domains/cli/reconcile_sender_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'onetime/operations/provision_sender_domain'

module Onetime
  module CLI
    # Reconcile a domain's Lettermint sender configuration.
    #
    # Handles two scenarios:
    #   1. Domain was deleted and re-added: the old Lettermint record
    #      causes a 409 duplicate. This command uses create_or_get_domain
    #      which handles 409 by fetching the existing record.
    #   2. Domain was added manually via Lettermint UI: this command
    #      creates the local MailerConfig and links it to the remote record.
    #
    class DomainsReconcileSenderCommand < Command
      include DomainsHelpers

      desc 'Reconcile Lettermint sender domain with local mailer config'

      argument :domain_name, type: :string, required: true, desc: 'Domain name (e.g. example.com)'

      option :from_address,
        type: :string,
        default: nil,
        desc: 'From address (default: existing mailer_config.from_address)'

      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Show what would happen without making changes'

      def call(domain_name:, from_address: nil, dry_run: false, **)
        boot_application!

        domain = load_domain_by_name(domain_name)
        return unless domain

        puts "Domain: #{domain.display_domain}"
        puts "  identifier: #{domain.identifier}"
        puts

        # Resolve mailer config and from_address
        existing_config = domain.mailer_config
        resolved_from   = from_address || existing_config&.from_address

        unless resolved_from && !resolved_from.empty?
          puts 'Error: No from_address available.'
          puts '  Provide --from-address or ensure the domain has an existing mailer config.'
          return
        end

        puts "  from_address: #{resolved_from}"
        puts "  existing config: #{existing_config ? 'yes' : 'no'}"
        puts

        if existing_config && existing_config.effective_provider != 'lettermint'
          puts "Error: Existing config uses provider '#{existing_config.effective_provider}', not 'lettermint'."
          puts '  Delete the existing sender config first to switch providers.'
          return
        end

        if dry_run
          puts '[dry-run] Would reconcile Lettermint sender domain:'
          puts "  domain: #{domain.display_domain}"
          puts "  from_address: #{resolved_from}"
          puts '  provider: lettermint'
          puts "  action: #{existing_config ? 'provision with existing config' : 'create new config, then provision'}"
          return
        end

        # Create mailer config if it doesn't exist
        mailer_config = existing_config
        unless mailer_config
          puts 'Creating mailer config...'
          begin
            mailer_config = Onetime::CustomDomain::MailerConfig.create!(
              domain_id: domain.identifier,
              from_address: resolved_from,
              provider: 'lettermint',
              enabled: false,
              sending_mode: 'platform',
            )
            puts "  created (domain_id: #{domain.identifier})"
          rescue StandardError => ex
            puts "Error creating mailer config: #{ex.message}"
            return
          end
        end

        # Provision via the operation (handles 409 by fetching existing)
        puts 'Provisioning sender domain with Lettermint...'
        result = Onetime::Operations::ProvisionSenderDomain.new(
          mailer_config: mailer_config,
        ).call

        if result.success?
          puts '  provisioned successfully'
          puts
          print_dns_records(result.dns_records)
          OT.info "[CLI] Reconciled sender domain: #{domain_name}"
        else
          puts "  failed: #{result.error}"
          OT.le "[CLI] Sender domain reconciliation failed: #{domain_name} - #{result.error}"
        end
      end

      private

      def print_dns_records(records)
        return if records.nil? || records.empty?

        puts 'DNS records to configure:'
        puts
        puts format('  %-8s %-45s %s', 'TYPE', 'NAME', 'VALUE')
        puts "  #{'-' * 8} #{'-' * 45} #{'-' * 40}"

        records.each do |record|
          rec_type  = record['type']  || record[:type]
          rec_name  = record['name']  || record[:name]
          rec_value = record['value'] || record[:value]

          puts format('  %-8s %-45s %s', rec_type, rec_name, rec_value)
        end
        puts
      end
    end
  end
end

Onetime::CLI.register 'domains reconcile-sender', Onetime::CLI::DomainsReconcileSenderCommand
