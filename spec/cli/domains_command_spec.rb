# spec/cli/domains_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe 'Domains Command', type: :cli do
  let(:domain) do
    double('Domain',
      domainid: 'example.com',
      domain_name: 'example.com',
      org_id: 'org123',
      verified: true,
      updated: Time.now.to_i,
      save: true
    )
  end

  let(:organization) do
    double('Organization',
      org_id: 'org123',
      display_name: 'Test Org',
      domains: ['example.com'],
      add_domain: true,
      remove_domain: true
    )
  end

  before do
    allow(Onetime::Models::Domain).to receive(:all).and_return([domain])
    allow(Onetime::Models::Organization).to receive(:load).and_return(organization)
  end

  describe 'without subcommand' do
    it 'lists all domains by default' do
      output = run_cli_command('domains')
      expect(output[:stdout]).to include('Domain Management')
    end
  end

  describe 'info subcommand' do
    it 'requires a domain name' do
      output = run_cli_command('domains', 'info')
      expect(output[:stdout]).to include('Error: Domain name required')
    end

    it 'displays domain information' do
      allow(Onetime::Models::Domain).to receive(:load).and_return(domain)

      output = run_cli_command('domains', 'info', 'example.com')
      expect(output[:stdout]).to include('Domain Information')
      expect(output[:stdout]).to include('example.com')
    end

    it 'handles non-existent domain' do
      allow(Onetime::Models::Domain).to receive(:load).and_return(nil)

      output = run_cli_command('domains', 'info', 'notfound.com')
      expect(output[:stdout]).to include('Domain not found')
    end
  end

  describe 'transfer subcommand' do
    it 'requires a domain name' do
      output = run_cli_command('domains', 'transfer')
      expect(output[:stdout]).to include('Error: Domain name required')
    end

    it 'requires --to-org option' do
      output = run_cli_command('domains', 'transfer', 'example.com')
      expect(output[:stdout]).to include('Error: --to-org required')
    end

    it 'transfers domain between organizations' do
      allow(Onetime::Models::Domain).to receive(:load).and_return(domain)
      allow(domain).to receive(:org_id=)
      expect(organization).to receive(:add_domain).with('example.com')

      output = run_cli_command('domains', 'transfer', 'example.com', '--to-org', 'org456')
      expect(output[:stdout]).to include('Transfer complete')
    end

    it 'handles transfer errors with rollback' do
      allow(Onetime::Models::Domain).to receive(:load).and_return(domain)
      allow(domain).to receive(:org_id=)
      allow(organization).to receive(:add_domain).and_raise('Test error')

      # Should rollback org_id
      expect(domain).to receive(:org_id=).with('org123')

      expect {
        run_cli_command('domains', 'transfer', 'example.com', '--to-org', 'org456')
      }.to raise_error(/Failed to add domain/)
    end
  end

  describe 'repair subcommand' do
    it 'requires a domain name' do
      output = run_cli_command('domains', 'repair')
      expect(output[:stdout]).to include('Error: Domain name required')
    end

    it 'detects and repairs domain issues' do
      allow(Onetime::Models::Domain).to receive(:load).and_return(domain)
      allow(organization).to receive(:domains).and_return([])  # Domain not in collection

      output = run_cli_command('domains', 'repair', 'example.com', '--run')
      expect(output[:stdout]).to include('Domain Repair')
    end
  end

  describe 'bulk-repair subcommand' do
    it 'finds and repairs all domain issues' do
      allow(Onetime::Models::Domain).to receive(:all).and_return([domain])
      allow(organization).to receive(:domains).and_return([])

      output = run_cli_command('domains', 'bulk-repair')
      expect(output[:stdout]).to include('Bulk Domain Repair')
    end

    it 'respects --run flag for actual repairs' do
      allow(Onetime::Models::Domain).to receive(:all).and_return([domain])
      allow(organization).to receive(:domains).and_return([])

      output = run_cli_command('domains', 'bulk-repair', '--run')
      expect(output[:stdout]).to include('repairs')
    end
  end

  describe 'orphaned subcommand' do
    it 'lists domains without organization' do
      orphaned_domain = double('Domain',
        domainid: 'orphaned.com',
        domain_name: 'orphaned.com',
        org_id: nil,
        verified: true
      )
      allow(Onetime::Models::Domain).to receive(:all).and_return([orphaned_domain])

      output = run_cli_command('domains', 'orphaned')
      expect(output[:stdout]).to include('Orphaned Domains')
    end
  end
end
