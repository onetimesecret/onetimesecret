# spec/cli/customers_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe 'Customers Command', type: :cli do
  let(:customer1) do
    double('Customer',
      custid: 'customer1@example.com',
      email: 'customer1@example.com',
      cust_domains: ['example.com']
    )
  end

  let(:customer2) do
    double('Customer',
      custid: 'customer2@example.com',
      email: 'customer2@example.com',
      cust_domains: []
    )
  end

  let(:mismatched_customer) do
    double('Customer',
      custid: 'old@example.com',
      email: 'new@example.com',
      cust_domains: []
    )
  end

  before do
    allow(Onetime::Models::Customer).to receive(:all).and_return([customer1, customer2])
  end

  describe '--list option' do
    it 'lists customer domains sorted by count' do
      output = run_cli_command('customers', '--list')
      expect(output[:stdout]).to include('Customer Domains')
    end

    it 'handles customers with no domains' do
      allow(Onetime::Models::Customer).to receive(:all).and_return([customer2])

      output = run_cli_command('customers', '--list')
      expect(output[:stdout]).to include('Customer Domains')
    end
  end

  describe '--check option' do
    it 'shows customers where custid and email do not match' do
      allow(Onetime::Models::Customer).to receive(:all).and_return([mismatched_customer])

      output = run_cli_command('customers', '--check')
      expect(output[:stdout]).to include('Customer Record Validation')
      expect(output[:stdout]).to include('CustID and email mismatch')
    end

    it 'handles nil customers safely' do
      allow(Onetime::Models::Customer).to receive(:all).and_return([nil, mismatched_customer])

      expect {
        run_cli_command('customers', '--check')
      }.not_to raise_error
    end

    it 'obscures email addresses in output' do
      allow(Onetime::Models::Customer).to receive(:all).and_return([mismatched_customer])
      allow(OT::Utils).to receive(:obscure_email).and_call_original

      output = run_cli_command('customers', '--check')
      expect(OT::Utils).to have_received(:obscure_email).at_least(:once)
    end

    it 'reports when all customers match' do
      allow(Onetime::Models::Customer).to receive(:all).and_return([customer1])

      output = run_cli_command('customers', '--check')
      expect(output[:stdout]).to include('All customers have matching custid and email')
    end
  end

  describe 'without options' do
    it 'displays usage information' do
      output = run_cli_command('customers')
      expect(output[:stdout]).to include('Customer Management')
    end
  end
end
