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

  describe 'list subcommand' do
    it 'lists customer domains sorted by count' do
      output = run_cli_command_quietly('customers', 'list')
      expect(output[:stdout]).to include('2 customers')
      expect(output[:stdout]).to include('example.com')
    end

    it 'handles customers with no domains' do
      instances_double = double('instances')
      allow(instances_double).to receive(:size).and_return(1)
      allow(instances_double).to receive(:all).and_return(['customer2@example.com'])
      allow(Onetime::Customer).to receive(:instances).and_return(instances_double)
      allow(Onetime::Customer).to receive(:load).with('customer2@example.com').and_return(customer2)

      output = run_cli_command_quietly('customers', 'list')
      expect(output[:stdout]).to include('1 customers')
    end
  end

  describe 'without options' do
    it 'displays customer count' do
      output = run_cli_command_quietly('customers')
      expect(output[:stdout]).to include('2 customers')
    end
  end

  # Common doubles for verify/unverify subcommands. The CLI commands are
  # thin orchestrators; the meaningful coverage of the underlying
  # state-change lives in
  # apps/web/auth/spec/operations/set_customer_verification_spec.rb.
  # These specs cover only the CLI translation layer.
  let(:target_customer) do
    double('Customer',
      email: 'target@example.com',
      objid: 'cust_target',
      extid: 'cust_ext_target',
      anonymous?: false,
    )
  end

  let(:verification_op) { instance_double(Auth::Operations::SetCustomerVerification) }

  before do
    allow(OT::Utils).to receive(:normalize_email).and_call_original
    allow(OT::Utils).to receive(:obscure_email).and_return('t***@example.com')
  end

  describe 'verify subcommand' do
    it 'reports success and exits 0 when the op returns :success' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .and_return(target_customer)
      allow(Auth::Operations::SetCustomerVerification).to receive(:new)
        .with(customer: target_customer, verified: true, verified_by: 'cli_provision')
        .and_return(verification_op)
      allow(verification_op).to receive(:call).and_return(:success)

      output = run_cli_command_quietly('customers', 'verify', 'target@example.com')
      expect(output[:stdout]).to include('Verified:')
      expect(last_exit_code).to eq(0)
    end

    it 'reports already-verified and exits 0 when the op returns :no_change' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .and_return(target_customer)
      allow(Auth::Operations::SetCustomerVerification).to receive(:new)
        .and_return(verification_op)
      allow(verification_op).to receive(:call).and_return(:no_change)

      output = run_cli_command_quietly('customers', 'verify', 'target@example.com')
      expect(output[:stdout]).to include('already verified')
      expect(last_exit_code).to eq(0)
    end

    it 'exits 1 with a friendly message when customer is not found' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)

      output = run_cli_command_quietly('customers', 'verify', 'missing@example.com')
      expect(output[:stdout]).to include('Customer not found')
      expect(last_exit_code).to eq(1)
    end

    it 'exits 1 when customer is anonymous' do
      allow(target_customer).to receive(:anonymous?).and_return(true)
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .and_return(target_customer)

      output = run_cli_command_quietly('customers', 'verify', 'target@example.com')
      expect(output[:stdout]).to include('anonymous')
      expect(last_exit_code).to eq(1)
    end

    it 'translates NoAuthDatabase to an actionable error and exits 1' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .and_return(target_customer)
      allow(Auth::Operations::SetCustomerVerification).to receive(:new)
        .and_return(verification_op)
      allow(verification_op).to receive(:call).and_raise(
        Auth::Operations::SetCustomerVerification::NoAuthDatabase,
        'Auth database unreachable',
      )

      output = run_cli_command_quietly('customers', 'verify', 'target@example.com')
      expect(output[:stdout]).to include('AUTH_DATABASE_URL')
      expect(last_exit_code).to eq(1)
    end

    it 'translates AccountNotFound to a sync-auth-accounts hint and exits 1' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .and_return(target_customer)
      allow(Auth::Operations::SetCustomerVerification).to receive(:new)
        .and_return(verification_op)
      allow(verification_op).to receive(:call).and_raise(
        Auth::Operations::SetCustomerVerification::AccountNotFound,
        'No Rodauth account for target@example.com',
      )

      output = run_cli_command_quietly('customers', 'verify', 'target@example.com')
      expect(output[:stdout]).to include('sync-auth-accounts')
      expect(last_exit_code).to eq(1)
    end
  end

  describe 'unverify subcommand' do
    it 'calls the op with verified: false and verified_by: nil' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .and_return(target_customer)
      allow(Auth::Operations::SetCustomerVerification).to receive(:new)
        .with(customer: target_customer, verified: false, verified_by: nil)
        .and_return(verification_op)
      allow(verification_op).to receive(:call).and_return(:success)

      output = run_cli_command_quietly('customers', 'unverify', 'target@example.com')
      expect(output[:stdout]).to include('Unverified:')
      expect(last_exit_code).to eq(0)
    end

    it 'reports already-unverified when the op returns :no_change' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .and_return(target_customer)
      allow(Auth::Operations::SetCustomerVerification).to receive(:new)
        .and_return(verification_op)
      allow(verification_op).to receive(:call).and_return(:no_change)

      output = run_cli_command_quietly('customers', 'unverify', 'target@example.com')
      expect(output[:stdout]).to include('already unverified')
      expect(last_exit_code).to eq(0)
    end

    it 'exits 1 when customer is not found' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)

      output = run_cli_command_quietly('customers', 'unverify', 'missing@example.com')
      expect(output[:stdout]).to include('Customer not found')
      expect(last_exit_code).to eq(1)
    end
  end
end
