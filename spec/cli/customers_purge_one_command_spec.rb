# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe Onetime::CLI::CustomersPurgeOneCommand do
  let(:command) { described_class.new }

  def purge_result(status:, blockers: [], actions: [], planned_actions: [], stage: nil, completed_stages: [])
    Auth::Operations::Customers::Purge::Result.new(
      status: status,
      extid: 'ur_target',
      custid: 'cust_target',
      blockers: blockers,
      actions: actions,
      planned_actions: planned_actions,
      stage: stage,
      completed_stages: completed_stages,
    )
  end

  def capture_stdout
    original = $stdout
    $stdout  = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe 'result output' do
    it 'prints Purged only for success' do
      success = capture_stdout do
        command.send(:output_result, purge_result(status: :success), email: 'v***@example.com', json: false)
      end

      expect(success).to eq("Purged v***@example.com (ur_target)\n")

      %i[refused partial not_found].each do |status|
        output = capture_stdout do
          command.send(:output_result, purge_result(status: status), email: 'v***@example.com', json: false)
        end
        expect(output).not_to include('Purged')
      end
    end

    it 'prints structured refusal blockers and says no mutation occurred' do
      result = purge_result(
        status: :refused,
        blockers: [{ code: :billing_state, org_id: 'org_blocked' }],
        planned_actions: [{ type: :remove_membership, org_id: 'org_other' }],
        stage: :preflight,
      )

      output = capture_stdout do
        command.send(:output_result, result, email: 'v***@example.com', json: false)
      end

      expect(output).to include('Purge refused')
      expect(output).to include('no mutation occurred')
      expect(output).to include('"code":"billing_state"')
      expect(output).to include('Stage: preflight')
    end

    it 'prints partial stage, completed stages, actions, and blockers' do
      result = purge_result(
        status: :partial,
        blockers: [{ code: :preflight_changed }],
        actions: [{ type: :remove_membership, org_id: 'org_done', status: :success }],
        stage: :post_cleanup_revalidation,
        completed_stages: [:remove_membership],
      )

      output = capture_stdout do
        command.send(:output_result, result, email: 'v***@example.com', json: false)
      end

      expect(output).to include('Purge partially completed')
      expect(output).to include('mutation began')
      expect(output).to include('Stage: post_cleanup_revalidation')
      expect(output).to include('Completed stages: remove_membership')
      expect(output).to include('"type":"remove_membership"')
      expect(output).to include('"code":"preflight_changed"')
    end

    it 'emits the stable JSON lifecycle contract' do
      result = purge_result(
        status: :refused,
        blockers: [{ code: :billing_state }],
        planned_actions: [{ type: :remove_membership }],
        stage: :preflight,
      )

      output = capture_stdout do
        command.send(:output_result, result, email: 'v***@example.com', json: true)
      end
      payload = JSON.parse(output)

      expect(payload.keys).to eq(%w[status deleted extid custid email blockers actions planned_actions stage completed_stages])
      expect(payload).to include(
        'status' => 'refused',
        'deleted' => false,
        'extid' => 'ur_target',
        'custid' => 'cust_target',
        'stage' => 'preflight',
      )
      expect(payload['blockers']).to eq([{ 'code' => 'billing_state' }])
    end
  end

  describe 'exit status' do
    it 'returns normally on success' do
      expect { command.send(:exit_for_result, purge_result(status: :success)) }.not_to raise_error
    end

    it 'exits nonzero for every non-success lifecycle status' do
      %i[refused partial not_found].each do |status|
        expect { command.send(:exit_for_result, purge_result(status: status)) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end
  end

  it 'explains preflight, blockers, and partial outcomes before confirmation' do
    customer = instance_double(Onetime::Customer,
      anonymous?: false,
      obscure_email: 'v***@example.com',
      extid: 'ur_target')
    allow(command).to receive(:boot_application!)
    allow(command).to receive(:resolve_customer).and_return(customer)

    original_stdin = $stdin
    $stdin = StringIO.new("n\n")
    output = capture_stdout do
      command.call(identifier: 'ur_target')
    end

    expect(output).to include('read-only organization preflight')
    expect(output).to include('Blockers refuse the purge without mutation')
    expect(output).to include('reported as partial; it does not imply rollback')
  ensure
    $stdin = original_stdin
  end
end
