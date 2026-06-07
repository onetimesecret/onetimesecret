# apps/api/domains/cli/reconcile_sender_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'
require 'onetime/operations/provision_sender_domain'

module Onetime
  module CLI
    # Reconcile a domain's sender configuration with its mail provider.
    #
    # Dispatches on the effective provider (SES, SendGrid, Lettermint),
    # so it works regardless of which provider a domain is configured for.
    #
    # Handles two scenarios:
    #   1. Domain was deleted and re-added: the old provider record
    #      causes a 409 duplicate. Provisioning handles 409 by fetching
    #      the existing record.
    #   2. Domain was added manually via the provider's UI: this command
    #      creates the local MailerConfig and links it to the remote record.
    #
    class DomainsReconcileSenderCommand < Command
      include DomainsHelpers

      desc 'Reconcile a sender domain with its local mailer config'

      argument :domain_name, type: :string, required: true, desc: 'Domain name (e.g. example.com)'

      option :from_address,
        type: :string,
        default: nil,
        desc: 'From address (default: existing mailer_config.from_address)'

      option :provider,
        type: :string,
        default: nil,
        desc: 'Provider for a new config (default: existing config or installation default)'

      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Show what would happen without making changes'

      def call(domain_name:, from_address: nil, provider: nil, dry_run: false, **)
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

        # Refuse to switch providers on an existing config: deleting the
        # config first ensures the old provider's sender identity is torn
        # down before a new one is created. effective_provider is already
        # normalized, so we only normalize the user-supplied option.
        if existing_config && provider && !provider.strip.empty? &&
           provider.strip.downcase != existing_config.effective_provider
          puts "Error: Existing config uses provider '#{existing_config.effective_provider}', not '#{provider}'."
          puts '  Delete the existing sender config first to switch providers.'
          return
        end

        resolved_provider = resolve_provider(provider, existing_config)
        valid_providers   = Onetime::CustomDomain::MailerConfig::PROVIDER_TYPES
        unless valid_providers.include?(resolved_provider)
          got = resolved_provider.empty? ? '' : " (got '#{resolved_provider}')"
          puts "Error: Could not resolve a valid sender provider#{got}."
          puts "  Provide --provider (one of: #{valid_providers.join(', ')})."
          return
        end

        puts "  from_address: #{resolved_from}"
        puts "  provider: #{resolved_provider}"
        puts "  existing config: #{existing_config ? 'yes' : 'no'}"
        puts

        if dry_run
          puts '[dry-run] Would reconcile sender domain:'
          puts "  domain: #{domain.display_domain}"
          puts "  from_address: #{resolved_from}"
          puts "  provider: #{resolved_provider}"
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
              provider: resolved_provider,
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
        puts "Provisioning sender domain with #{resolved_provider}..."
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

      # Resolve which provider to reconcile against.
      #
      # Precedence:
      #   1. Explicit --provider option
      #   2. Existing config's effective_provider (already normalized)
      #   3. Installation-level sender provider (Mailer.determine_sender_provider)
      #
      # @param provider_opt [String, nil] Value of the --provider option
      # @param existing_config [CustomDomain::MailerConfig, nil] Existing config
      # @return [String] Lowercased provider name, or '' when unresolvable
      def resolve_provider(provider_opt, existing_config)
        provider = provider_opt.to_s.strip.downcase
        return provider unless provider.empty?

        provider = existing_config&.effective_provider.to_s
        return provider unless provider.empty?

        Onetime::Mail::Mailer.determine_sender_provider.to_s.strip.downcase
      end

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
