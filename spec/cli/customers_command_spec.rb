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

  describe 'without options' do
    it 'displays customer count' do
      output = run_cli_command_quietly('customers')
      expect(output[:stdout]).to include('2 customers')
    end
  end
end
