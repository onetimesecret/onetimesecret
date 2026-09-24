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
    allow(Onetime::Customer).to receive(:find_by_email).and_return(customer)
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
end
