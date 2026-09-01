# spec/cli/customers_impersonate_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

# The CLI spec helper mocks OT.boot!, so the auth operations namespace is not
# autoloaded. These specs stub Auth::Operations::Customers::Impersonate.new,
# which requires the constant to exist at stub time — load it explicitly.
require 'auth/operations/customers/impersonate'

# The CLI command is a thin adapter: the meaningful coverage of grant issuance +
# audit lives in apps/web/auth/spec/operations/customers/impersonate_spec.rb.
# These specs cover only the CLI translation layer — mandatory --operator /
# --reason, confirmation, and output.
RSpec.describe 'Customers Impersonate Command', type: :cli do
  let(:customer) do
    double('Customer',
      email: 'target@example.com',
      extid: 'ur_target',
      obscure_email: 't****t@example.com',
      anonymous?: false,
    )
  end

  let(:op) { instance_double(Auth::Operations::Customers::Impersonate) }

  let(:result) do
    Auth::Operations::Customers::Impersonate::Result.new(
      status: :issued,
      customer: customer,
      actor: 'ur_operator',
      reason: 'ticket #123',
      token: 'secret-bearer-token',
      grant_id: 'grant-uuid-123',
      expires_in: 120,
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT::Utils).to receive(:normalize_email).and_call_original
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(customer)
    allow(Auth::Operations::Customers::Impersonate).to receive(:new).and_return(op)
    allow(op).to receive(:call).and_return(result)
  end

  describe 'validation' do
    it 'refuses without --operator' do
      output = run_cli_command_quietly(
        'customers', 'impersonate', 'target@example.com', '--reason', 'x', '--yes'
      )
      expect(output[:stdout]).to include('--operator is required')
      expect(last_exit_code).to eq(1)
      expect(Auth::Operations::Customers::Impersonate).not_to have_received(:new)
    end

    it 'refuses without --reason' do
      output = run_cli_command_quietly(
        'customers', 'impersonate', 'target@example.com', '--operator', 'ur_operator', '--yes'
      )
      expect(output[:stdout]).to include('--reason is required')
      expect(last_exit_code).to eq(1)
      expect(Auth::Operations::Customers::Impersonate).not_to have_received(:new)
    end

    it 'refuses when the customer is not found' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
      output = run_cli_command_quietly(
        'customers', 'impersonate', 'ghost@example.com',
        '--operator', 'ur_operator', '--reason', 'x', '--yes'
      )
      expect(output[:stdout]).to include('Customer not found')
      expect(last_exit_code).to eq(1)
    end
  end

  describe 'issuance' do
    it 'invokes the op with the operator as actor and prints the grant' do
      output = run_cli_command_quietly(
        'customers', 'impersonate', 'target@example.com',
        '--operator', 'ur_operator', '--reason', 'ticket #123', '--yes'
      )

      expect(Auth::Operations::Customers::Impersonate).to have_received(:new).with(
        customer: customer,
        actor: 'ur_operator',
        reason: 'ticket #123',
        ttl: nil,
      )
      expect(output[:stdout]).to include('Impersonation grant issued')
      expect(output[:stdout]).to include('secret-bearer-token')
      expect(output[:stdout]).to include('grant-uuid-123')
    end

    it 'passes an explicit --ttl through as an integer' do
      run_cli_command_quietly(
        'customers', 'impersonate', 'target@example.com',
        '--operator', 'ur_operator', '--reason', 'x', '--ttl', '300', '--yes'
      )
      expect(Auth::Operations::Customers::Impersonate).to have_received(:new).with(
        hash_including(ttl: 300)
      )
    end

    it 'emits machine-readable JSON with --json (implies non-interactive)' do
      output = run_cli_command_quietly(
        'customers', 'impersonate', 'target@example.com',
        '--operator', 'ur_operator', '--reason', 'x', '--yes', '--json'
      )
      parsed = JSON.parse(output[:stdout])
      expect(parsed['status']).to eq('issued')
      expect(parsed['extid']).to eq('ur_target')
      expect(parsed['grant_id']).to eq('grant-uuid-123')
      expect(parsed['token']).to eq('secret-bearer-token')
    end

    it 'refuses to proceed non-interactively in --json without --yes' do
      output = run_cli_command_quietly(
        'customers', 'impersonate', 'target@example.com',
        '--operator', 'ur_operator', '--reason', 'x', '--json'
      )
      expect(last_exit_code).to eq(1)
      expect(Auth::Operations::Customers::Impersonate).not_to have_received(:new)
      expect(output[:stdout]).to include('Refusing to impersonate without --yes')
    end
  end

  describe 'op-raised guards surface as CLI errors' do
    it 'maps PrivilegedTarget to a non-zero exit' do
      allow(op).to receive(:call)
        .and_raise(Auth::Operations::Customers::Impersonate::PrivilegedTarget, 'no colonels')
      output = run_cli_command_quietly(
        'customers', 'impersonate', 'target@example.com',
        '--operator', 'ur_operator', '--reason', 'x', '--yes'
      )
      expect(output[:stdout]).to include('no colonels')
      expect(last_exit_code).to eq(1)
    end
  end
end
