# spec/cli/customers_doctor_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'
require 'onetime/cli/customers/doctor_command'
require 'auth/operations/customers/doctor'

RSpec.describe 'customers doctor', type: :cli do
  let(:customer) do
    double(
      'Customer',
      objid: 'cust_1',
      extid: 'ur_current',
      obscure_email: 'us***@e***.com',
    )
  end
  let(:op) { instance_double(Auth::Operations::Customers::Doctor) }
  let(:issue) do
    {
      check: :workspace_collision_phantom_index,
      classification: :phantom_index,
      severity: :high,
      message: 'contact_email_index points to a missing organization',
      repairable: true,
      repair_action: 'Compare-and-delete the unchanged stale claim',
    }
  end

  before do
    # The command resolves through Customers::Shared#resolve_customer.
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(customer)
    allow(Auth::Operations::Customers::Doctor).to receive(:new).and_return(op)
    allow(op).to receive(:call).and_return(
      Auth::Operations::Customers::Doctor::Report.new(
        issues: [],
        repaired: [
          {
            customer: 'ur_current',
            action: :workspace_collision_repaired,
            classification: :phantom_index,
            org: 'on_current',
          },
        ],
      ),
    )
  end

  it 'threads repair audit attribution and renders the collision repair' do
    output = run_cli_command_quietly(
      'customers', 'doctor', 'user@example.com', '--repair',
    )

    expect(Auth::Operations::Customers::Doctor).to have_received(:new).with(
      customer: customer,
      repair: true,
      actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
    )
    expect(output[:stdout]).to include('repaired phantom_index collision and provisioned workspace on_current')
    expect(output[:stdout]).to include('Healthy: 1')
    expect(last_exit_code).to eq(0)
  end

  it 'preserves the classification code in JSON output' do
    output = run_cli_command_quietly(
      'customers', 'doctor', 'user@example.com', '--repair', '--json',
    )
    payload = JSON.parse(output[:stdout])

    expect(payload['issues']).to be_empty
    expect(payload.dig('repaired', 0, 'classification')).to eq('phantom_index')
    expect(payload.dig('repaired', 0, 'org')).to eq('on_current')
  end

  it 'returns failure and never reports healthy when provisioning retry remains latched' do
    retry_issue = issue.merge(
      check: :workspace_provisioning_retry_failed,
      message: 'Default-workspace provisioning failed after the stale claim was removed',
      repairable: false,
      repair_failed: true,
      partial: true,
    )
    allow(op).to receive(:call).and_return(
      Auth::Operations::Customers::Doctor::Report.new(issues: [retry_issue], repaired: []),
    )

    outputs = 2.times.map do
      output = run_cli_command_quietly(
        'customers', 'doctor', 'user@example.com', '--repair',
      )
      [output, last_exit_code]
    end

    outputs.each do |output, exit_code|
      expect(output[:stdout]).to include('Healthy: 0')
      expect(output[:stdout]).not_to include('Repaired:')
      expect(exit_code).to eq(1)
    end
    expect(op).to have_received(:call).twice
  end

  # bin/ots resolves simple auth mode whenever AUTHENTICATION_MODE is not
  # exported into its shell. The workspace repairs re-run
  # EnsureDefaultWorkspace with the default flag, and in that state
  # Customer#federation_claim_deferred? reads no verification step, so on a
  # full-mode install a repair would claim a pending federated subscription
  # for an account nobody has verified (#4754 review, F1). The audit is not
  # gated. The unit lane exports AUTHENTICATION_MODE=simple, so the examples
  # above run with the mode settled.
  describe 'when simple auth mode was resolved by default' do
    before { allow(Onetime.auth_config).to receive(:simple_by_default?).and_return(true) }

    it 'refuses --repair before resolving the customer' do
      output = run_cli_command_quietly('customers', 'doctor', 'user@example.com', '--repair')

      expect(Onetime::Customer).not_to have_received(:load_by_extid_or_email)
      expect(Auth::Operations::Customers::Doctor).not_to have_received(:new)
      expect(output[:stdout]).to include('Error: AUTHENTICATION_MODE is not set')
      expect(output[:stdout]).to include('Export AUTHENTICATION_MODE=full')
      expect(last_exit_code).to eq(1)
    end

    it 'refuses a --repair sweep the same way, as JSON' do
      output = run_cli_command_quietly('customers', 'doctor', '--all', '--repair', '--json')

      expect(Auth::Operations::Customers::Doctor).not_to have_received(:new)
      expect(JSON.parse(output[:stdout])['error']).to include('AUTHENTICATION_MODE is not set')
      expect(last_exit_code).to eq(1)
    end

    it 'still audits without --repair' do
      allow(op).to receive(:call).and_return(
        Auth::Operations::Customers::Doctor::Report.new(issues: [], repaired: []),
      )

      output = run_cli_command_quietly('customers', 'doctor', 'user@example.com')

      expect(Auth::Operations::Customers::Doctor).to have_received(:new).with(
        customer: customer, repair: false, actor: nil,
      )
      expect(output[:stdout]).to include('Healthy: 1')
      expect(last_exit_code).to eq(0)
    end
  end
end
