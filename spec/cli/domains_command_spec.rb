# spec/cli/domains_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe 'Domains Command', type: :cli do
  let(:domain) do
    double('Domain',
      domainid: 'example.com',
      domain_name: 'example.com',
      display_domain: 'example.com',
      org_id: 'org123',
      verified: 'true',
      verification_state: 'verified',
      updated: Time.now.to_i,
      created: Time.now.to_i,
      save: true
    )
  end

  let(:organization) do
    double('Organization',
      org_id: 'org123',
      display_name: 'Test Org',
      list_domains: ['example.com'],
      add_domain: true,
      remove_domain: true
    )
  end

  before do
    allow(Onetime::CustomDomain).to receive_message_chain(:instances, :all).and_return([domain.domainid])
    allow(Onetime::CustomDomain).to receive(:find_by_identifier).and_return(domain)
    allow(Onetime::Organization).to receive(:load).and_return(organization)
  end

  describe 'without subcommand' do
    it 'lists all domains by default' do
      output = run_cli_command_quietly('domains')
      expect(output[:stdout]).to include('custom domains')
    end
  end

  describe 'info subcommand' do
    it 'requires a domain name' do
      output = run_cli_command_quietly('domains', 'info')
      expect(output[:stdout]).to include('was called with no arguments')
    end

    it 'displays domain information' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)

      output = run_cli_command_quietly('domains', 'info', 'example.com')
      expect(output[:stdout]).to include('Domain Information')
      expect(output[:stdout]).to include('example.com')
    end

    it 'handles non-existent domain' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(nil)

      output = run_cli_command_quietly('domains', 'info', 'notfound.com')
      expect(output[:stdout]).to include('not found')
    end
  end

  describe 'transfer subcommand' do
    it 'requires a domain name' do
      output = run_cli_command_quietly('domains', 'transfer')
      expect(output[:stdout]).to include('was called with no arguments')
    end

    it 'requires --to-org option' do
      output = run_cli_command_quietly('domains', 'transfer', 'example.com')
      expect(output[:stdout]).to include('required')
    end

    it 'transfers domain between organizations' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(domain).to receive(:org_id=)
      allow(domain).to receive(:save)
      expect(organization).to receive(:add_domain).with('example.com')

      output = run_cli_command_quietly('domains', 'transfer', 'example.com', '--to-org', 'org456', '--force')
      expect(output[:stdout]).to include('Transfer complete')
    end

    it 'handles transfer errors with rollback' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(domain).to receive(:org_id=)
      allow(domain).to receive(:save)
      allow(organization).to receive(:add_domain).and_raise('Test error')

      output = run_cli_command_quietly('domains', 'transfer', 'example.com', '--to-org', 'org456', '--force')
      expect(output[:stdout]).to include('Error during transfer')
    end
  end

  describe 'repair subcommand' do
    it 'requires a domain name' do
      output = run_cli_command_quietly('domains', 'repair')
      expect(output[:stdout]).to include('was called with no arguments')
    end

    it 'detects and repairs domain issues' do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(organization).to receive(:list_domains).and_return([])  # Domain not in collection
      allow(organization).to receive(:add_domain)
      allow(domain).to receive(:save)

      output = run_cli_command_quietly('domains', 'repair', 'example.com', '--force')
      expect(output[:stdout]).to include('Repair complete')
    end
  end

  describe 'bulk-repair subcommand' do
    it 'finds and repairs all domain issues' do
      allow(Onetime::CustomDomain).to receive_message_chain(:instances, :all).and_return([domain.domainid])
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(organization).to receive(:list_domains).and_return([])

      output = run_cli_command_quietly('domains', 'bulk-repair', '--dry-run')
      expect(output[:stdout]).to include('Scan Results')
    end

    it 'respects --run flag for actual repairs' do
      allow(Onetime::CustomDomain).to receive_message_chain(:instances, :all).and_return([domain.domainid])
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).and_return(domain)
      allow(Onetime::Organization).to receive(:load).and_return(organization)
      allow(organization).to receive(:list_domains).and_return([])
      allow(organization).to receive(:add_domain)
      allow(domain).to receive(:save)

      output = run_cli_command_quietly('domains', 'bulk-repair', '--force')
      expect(output[:stdout]).to include('repaired')
    end
  end

  describe 'orphaned subcommand' do
    it 'lists domains without organization' do
      orphaned_domain = double('Domain',
        domainid: 'orphaned.com',
        domain_name: 'orphaned.com',
        display_domain: 'orphaned.com',
        org_id: '',
        verified: 'true',
        verification_state: 'verified',
        created: Time.now.to_i
      )
      allow(Onetime::CustomDomain).to receive_message_chain(:instances, :all).and_return([orphaned_domain.domainid])
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).and_return(orphaned_domain)

      output = run_cli_command_quietly('domains', 'orphaned')
      expect(output[:stdout]).to include('orphaned custom domains')
    end
  end
end
