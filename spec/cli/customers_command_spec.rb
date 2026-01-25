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
    # Mock Onetime::Customer (Familia model) instances
    instances_double = double('instances')
    allow(instances_double).to receive(:size).and_return(2)
    allow(instances_double).to receive(:all).and_return(['customer1@example.com', 'customer2@example.com'])
    allow(Onetime::Customer).to receive(:instances).and_return(instances_double)
    allow(Onetime::Customer).to receive(:load).with('customer1@example.com').and_return(customer1)
    allow(Onetime::Customer).to receive(:load).with('customer2@example.com').and_return(customer2)
  end

  describe '--list option' do
    it 'lists customer domains sorted by count' do
      output = run_cli_command_quietly('customers', '--list')
      expect(output[:stdout]).to include('2 customers')
      expect(output[:stdout]).to include('example.com')
    end

    it 'handles customers with no domains' do
      instances_double = double('instances')
      allow(instances_double).to receive(:size).and_return(1)
      allow(instances_double).to receive(:all).and_return(['customer2@example.com'])
      allow(Onetime::Customer).to receive(:instances).and_return(instances_double)
      allow(Onetime::Customer).to receive(:load).with('customer2@example.com').and_return(customer2)

      output = run_cli_command_quietly('customers', '--list')
      expect(output[:stdout]).to include('1 customers')
    end
  end

  describe '--check option' do
    it 'shows customers where custid and email do not match' do
      instances_double = double('instances')
      allow(instances_double).to receive(:size).and_return(1)
      allow(instances_double).to receive(:all).and_return(['old@example.com'])
      allow(Onetime::Customer).to receive(:instances).and_return(instances_double)
      allow(Onetime::Customer).to receive(:load).with('old@example.com').and_return(mismatched_customer)

      output = run_cli_command_quietly('customers', '--check')
      expect(output[:stdout]).to include('1 customers')
      expect(output[:stdout]).to include('CustID and email mismatch')
    end

    it 'handles nil customers safely' do
      instances_double = double('instances')
      allow(instances_double).to receive(:size).and_return(2)
      allow(instances_double).to receive(:all).and_return(['nil', 'old@example.com'])
      allow(Onetime::Customer).to receive(:instances).and_return(instances_double)
      allow(Onetime::Customer).to receive(:load).with('nil').and_return(nil)
      allow(Onetime::Customer).to receive(:load).with('old@example.com').and_return(mismatched_customer)

      expect {
        run_cli_command_quietly('customers', '--check')
      }.not_to raise_error
    end

    it 'obscures email addresses in output' do
      instances_double = double('instances')
      allow(instances_double).to receive(:size).and_return(1)
      allow(instances_double).to receive(:all).and_return(['old@example.com'])
      allow(Onetime::Customer).to receive(:instances).and_return(instances_double)
      allow(Onetime::Customer).to receive(:load).with('old@example.com').and_return(mismatched_customer)
      allow(OT::Utils).to receive(:obscure_email).and_call_original

      output = run_cli_command_quietly('customers', '--check')
      expect(OT::Utils).to have_received(:obscure_email).at_least(:once)
    end

    it 'reports when all customers match' do
      instances_double = double('instances')
      allow(instances_double).to receive(:size).and_return(2)
      allow(instances_double).to receive(:all).and_return(['customer1@example.com', 'customer2@example.com'])
      allow(Onetime::Customer).to receive(:instances).and_return(instances_double)
      allow(Onetime::Customer).to receive(:load).with('customer1@example.com').and_return(customer1)
      allow(Onetime::Customer).to receive(:load).with('customer2@example.com').and_return(customer2)

      output = run_cli_command_quietly('customers', '--check')
      expect(output[:stdout]).to include('All customers have matching custid and email')
    end
  end

  describe 'without options' do
    it 'displays customer count' do
      output = run_cli_command_quietly('customers')
      expect(output[:stdout]).to include('2 customers')
    end
  end
end
