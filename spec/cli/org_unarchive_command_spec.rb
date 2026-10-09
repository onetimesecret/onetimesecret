# spec/cli/org_unarchive_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots org unarchive ORG [--run] [--force]` (#4717).
#
# Pure adapter coverage: org resolution, the dry-run-by-default flow (no --run
# means plan only, exit 0, nothing written), --run applying once, --force
# threading, --json, and the status -> exit-code + operator-guidance mapping.
# The guard, the clear and the audit event are the op's job and are covered
# (against a real datastore) by spec/unit/onetime/operations/org/unarchive_spec.rb,
# so here the op is stubbed at its constructor.
#
# Unlike `org delete` / `org transfer-ownership` there is no confirmation
# prompt: the default IS the dry run, and --run is the explicit apply (the
# `bin/ots migrations …` convention). The op is therefore constructed exactly
# once per invocation.
#
# Run: tests/lanes/run unit --only spec/cli/org_unarchive_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; these are also listed in the
# lib/onetime/cli.rb manifest. Required here so the spec is independent of
# manifest ordering.
require 'onetime/cli/org/shared'
require 'onetime/cli/org/unarchive_command'

RSpec.describe 'Org Unarchive Command', type: :cli do
  let(:organization) do
    double(
      'Organization',
      objid: 'org-obj-1',
      extid: 'on_org_ext',
      display_name: 'Test Org',
    )
  end
  let(:archived_comment) { 'Superseded by domain org on_org_ext via SSO self-heal' }

  def result_with(status:, dry_run:, **overrides)
    Onetime::Operations::Org::Unarchive::Result.new(
      **{
        status: status,
        org_id: 'on_org_ext',
        display_name: 'Test Org',
        owner_id: 'ur_owner_ext',
        pointer_org_id: nil,
        archived_comment: archived_comment,
        force: false,
        dry_run: dry_run,
      }.merge(overrides)
    )
  end

  let(:plan_result)    { result_with(status: :planned, dry_run: true) }
  let(:applied_result) { result_with(status: :success, dry_run: false) }
  let(:op_calls)       { [] }

  before do
    allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(organization)
    allow(Onetime::Organization).to receive(:load).and_return(nil)

    allow(Onetime::Operations::Org::Unarchive).to receive(:new) do |args|
      op_calls << args
      instance_double(
        Onetime::Operations::Org::Unarchive,
        call: args[:dry_run] ? plan_result : applied_result,
      )
    end
  end

  describe 'resolution' do
    it 'exits 1 when the org cannot be resolved' do
      output = run_cli_command_quietly('org', 'unarchive', 'on_nope')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: on_nope')
      expect(Onetime::Operations::Org::Unarchive).not_to have_received(:new)
    end

    it 'falls back to Organization.load for an objid (Org::Shared#resolve_org)' do
      allow(Onetime::Organization).to receive(:load).with('org-obj-1').and_return(organization)

      run_cli_command_quietly('org', 'unarchive', 'org-obj-1')

      expect(last_exit_code).to eq(0)
      expect(op_calls.last).to include(org: organization)
    end
  end

  describe 'dry run by default' do
    it 'plans, prints what would be cleared, writes nothing and exits 0 without --run' do
      output = run_cli_command_quietly('org', 'unarchive', 'on_org_ext')

      expect(last_exit_code).to eq(0)
      expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
      expect(output[:stdout]).to include('DRY RUN')
      expect(output[:stdout]).to include('on_org_ext (Test Org)')
      expect(output[:stdout]).to include(archived_comment)
      expect(output[:stdout]).to include('--run')
    end

    it 'never prompts' do
      allow($stdin).to receive(:gets).and_return("y\n")

      run_cli_command_quietly('org', 'unarchive', 'on_org_ext')
      run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--run')

      expect($stdin).not_to have_received(:gets)
    end

    it 'emits the plan as JSON under --json' do
      output = run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--json')

      expect(last_exit_code).to eq(0)
      payload = JSON.parse(output[:stdout])
      expect(payload).to include('status' => 'planned', 'org_id' => 'on_org_ext', 'dry_run' => true)
    end
  end

  describe 'op invocation' do
    it 'passes the resolved org, the CLI sentinel actor, dry_run: true and force: false by default' do
      run_cli_command_quietly('org', 'unarchive', 'on_org_ext')

      expect(op_calls.size).to eq(1)
      expect(op_calls.last).to include(
        org: organization,
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        dry_run: true,
        force: false,
      )
    end

    it '--run applies exactly once with dry_run: false' do
      run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--run')

      expect(op_calls.map { |args| args[:dry_run] }).to eq([false])
    end

    it 'threads --force through to the op' do
      run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--run', '--force')

      expect(op_calls.last).to include(dry_run: false, force: true)
    end

    it 'uses --force on the plan pass too' do
      run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--force')

      expect(op_calls.last).to include(dry_run: true, force: true)
    end

    it 'never audits from the adapter (the op owns the single event)' do
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      allow(Onetime::ColonelAuditEvent).to receive(:record_access)

      run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--run')

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
    end
  end

  describe 'statuses' do
    def stub_op_result(result)
      allow(Onetime::Operations::Org::Unarchive).to receive(:new).and_return(
        instance_double(Onetime::Operations::Org::Unarchive, call: result),
      )
    end

    it ':not_archived exits 0 and says so' do
      stub_op_result(result_with(status: :not_archived, dry_run: false, archived_comment: nil))

      output = run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--run')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('on_org_ext')
      expect(output[:stdout]).to match(/not archived/i)
    end

    it ':default_pointer_elsewhere exits 1, names the other org and points at --force' do
      stub_op_result(result_with(status: :default_pointer_elsewhere, dry_run: false, pointer_org_id: 'on_other_ext'))

      output = run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--run')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('on_other_ext')
      expect(output[:stdout]).to include('--force')
    end

    it ':default_pointer_elsewhere refuses on the plan pass with the same guidance' do
      stub_op_result(result_with(status: :default_pointer_elsewhere, dry_run: true, pointer_org_id: 'on_other_ext'))

      output = run_cli_command_quietly('org', 'unarchive', 'on_org_ext')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('--force')
    end

    it 'exits 1 on a refusal in --json mode, with the status and pointer in the payload' do
      stub_op_result(result_with(status: :default_pointer_elsewhere, dry_run: false, pointer_org_id: 'on_other_ext'))

      output = run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--run', '--json')

      expect(last_exit_code).to eq(1)
      payload = JSON.parse(output[:stdout])
      expect(payload).to include('status' => 'default_pointer_elsewhere', 'pointer_org_id' => 'on_other_ext')
    end
  end

  describe 'applied output' do
    it 'reports the unarchive' do
      output = run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--run')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Unarchived on_org_ext (Test Org)')
    end

    it 'emits the full JSON payload under --run --json' do
      output = run_cli_command_quietly('org', 'unarchive', 'on_org_ext', '--run', '--json')

      payload = JSON.parse(output[:stdout])
      expect(payload).to include(
        'status' => 'success',
        'org_id' => 'on_org_ext',
        'display_name' => 'Test Org',
        'owner_id' => 'ur_owner_ext',
        'pointer_org_id' => nil,
        'archived_comment' => archived_comment,
        'force' => false,
        'dry_run' => false,
      )
    end
  end
end
