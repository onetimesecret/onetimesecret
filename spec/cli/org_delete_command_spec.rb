# spec/cli/org_delete_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots org delete` (#4204).
#
# Pure adapter coverage: org resolution, the plan-then-prompt flow (the reason
# the op's dry_run defaults to true), --dry-run winning over --yes, the --json
# refusal, the interactive decline, the force-flag threading, and the
# guardrail-status -> exit-code + operator-guidance mapping. The teardown, the
# guardrails themselves and the audit event are the op's job and are covered
# (against a real datastore) by
# spec/unit/onetime/operations/org/delete_spec.rb, so here the op is stubbed at
# its constructor.
#
# Run: bundle exec rspec spec/cli/org_delete_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; these are also listed in the
# lib/onetime/cli.rb manifest. Required here so the spec is independent of
# manifest ordering.
require 'onetime/cli/org/shared'
require 'onetime/cli/org/delete_command'

RSpec.describe 'Org Delete Command', type: :cli do
  let(:organization) do
    double(
      'Organization',
      objid: 'org-obj-1',
      extid: 'on_org_ext',
      display_name: 'Test Org',
    )
  end

  def result_with(status:, dry_run:, **overrides)
    Onetime::Operations::Org::Delete::Result.new(
      **{
        status: status,
        org_id: 'on_org_ext',
        display_name: 'Test Org',
        planid: 'free_v1',
        members: [{ extid: 'ur_a', email: 'a@example.com' }],
        members_notified: 1,
        pending_invitations: 2,
        domain_count: 0,
        domains: [],
        drifted_domains: [],
        is_default: false,
        active_subscription: false,
        owner_id: 'ur_a',
        owner_org_count: 2,
        default_org_cleared: ['ur_a'],
        dry_run: dry_run,
      }.merge(overrides)
    )
  end

  # The interactive path calls the op TWICE — once to build the plan
  # (dry_run: true), once to apply. Hand back whichever result the example
  # configured for that phase, and record the constructor args in order.
  let(:plan_result)    { result_with(status: :planned, dry_run: true) }
  let(:applied_result) { result_with(status: :success, dry_run: false) }
  let(:op_calls)       { [] }

  before do
    allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(organization)
    allow(Onetime::Organization).to receive(:load).and_return(nil)

    allow(Onetime::Operations::Org::Delete).to receive(:new) do |args|
      op_calls << args
      instance_double(
        Onetime::Operations::Org::Delete,
        call: args[:dry_run] ? plan_result : applied_result,
      )
    end
  end

  describe 'resolution' do
    it 'exits 1 when the org cannot be resolved' do
      output = run_cli_command_quietly('org', 'delete', 'on_nope', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: on_nope')
      expect(Onetime::Operations::Org::Delete).not_to have_received(:new)
    end

    it 'resolves the org BEFORE prompting' do
      allow($stdin).to receive(:gets).and_return("y\n")

      run_cli_command_quietly('org', 'delete', 'on_nope')

      expect(last_exit_code).to eq(1)
      expect($stdin).not_to have_received(:gets)
    end
  end

  describe 'plan-then-prompt (why the op dry-runs by default)' do
    it 'names everything the delete destroys before asking' do
      allow($stdin).to receive(:gets).and_return("y\n")

      output = run_cli_command_quietly('org', 'delete', 'on_org_ext')

      expect(output[:stdout]).to include('DRY RUN — nothing has been written yet')
      expect(output[:stdout]).to include('Organization:   on_org_ext (Test Org)')
      expect(output[:stdout]).to include('Plan:           free_v1')
      expect(output[:stdout]).to include('  - ur_a  a@example.com')
      expect(output[:stdout]).to include('Invitations:    2 pending')
      expect(output[:stdout]).to include('default_org_id: cleared for ur_a')
      expect(op_calls.map { |args| args[:dry_run] }).to eq([true, false])
    end

    it 'aborts without applying when the confirmation is declined' do
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('org', 'delete', 'on_org_ext')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Aborted.')
      expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
    end

    it 'skips the plan pass entirely under --yes' do
      run_cli_command_quietly('org', 'delete', 'on_org_ext', '--yes')

      expect(op_calls.map { |args| args[:dry_run] }).to eq([false])
    end

    it '--dry-run wins over --yes and never applies' do
      output = run_cli_command_quietly('org', 'delete', 'on_org_ext', '--dry-run', '--yes')

      expect(last_exit_code).to eq(0)
      expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
      expect(output[:stdout]).to include('Dry run only — re-run without --dry-run to apply.')
    end

    it 'refuses to delete without --yes in --json mode' do
      output = run_cli_command_quietly('org', 'delete', 'on_org_ext', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])['error'])
        .to eq('Refusing to delete without --yes in --json mode')
      expect(Onetime::Operations::Org::Delete).not_to have_received(:new)
    end

    it 'allows --json --dry-run without --yes (it writes nothing)' do
      output = run_cli_command_quietly('org', 'delete', 'on_org_ext', '--json', '--dry-run')

      expect(last_exit_code).to eq(0)
      expect(JSON.parse(output[:stdout])['status']).to eq('planned')
      expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
    end
  end

  describe 'op invocation' do
    it 'passes the resolved org, the CLI sentinel actor and no forces by default' do
      run_cli_command_quietly('org', 'delete', 'on_org_ext', '--yes')

      expect(op_calls.last).to include(
        org: organization,
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        dry_run: false,
        force_default: false,
        force_subscription: false,
      )
    end

    it 'threads each force flag through independently' do
      run_cli_command_quietly('org', 'delete', 'on_org_ext', '--yes', '--force-default')

      expect(op_calls.last).to include(force_default: true, force_subscription: false)
    end

    it 'uses the same force flags on the plan pass as on the apply' do
      allow($stdin).to receive(:gets).and_return("y\n")

      run_cli_command_quietly('org', 'delete', 'on_org_ext', '--force-subscription')

      expect(op_calls.map { |args| args[:force_subscription] }).to eq([true, true])
    end

    # #4338 — the shell peer of the console's reason field. Same flag name,
    # same wording and same blank-means-absent rule on every destructive CLI
    # verb; the op turns it into `detail[:reason]`.
    it 'threads --reason through to the op' do
      run_cli_command_quietly(
        'org', 'delete', 'on_org_ext', '--yes', '--reason', 'closing dormant workspace',
      )

      expect(op_calls.last).to include(reason: 'closing dormant workspace')
    end

    # OPTIONAL rollout: omitting it must reach the op as nil, so the op's own
    # normalization keeps the audit detail byte-identical to its pre-#4338 shape.
    it 'passes reason: nil when the flag is omitted' do
      run_cli_command_quietly('org', 'delete', 'on_org_ext', '--yes')

      expect(op_calls.last).to include(reason: nil)
    end

    # The plan pass and the apply pass must agree, exactly as they do on the
    # force flags — the op records the reason on BOTH the preview observation
    # and the applied event.
    it 'uses the same reason on the plan pass as on the apply' do
      allow($stdin).to receive(:gets).and_return("y\n")

      run_cli_command_quietly('org', 'delete', 'on_org_ext', '--reason', 'support req 22')

      expect(op_calls.map { |args| args[:reason] }).to eq(['support req 22', 'support req 22'])
    end

    it 'never audits from the adapter (the op owns the single event)' do
      allow(Onetime::ColonelAuditEvent).to receive(:record)

      run_cli_command_quietly('org', 'delete', 'on_org_ext', '--yes')

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe 'guardrail refusals' do
    # Each guard exits non-zero and names its own remediation — and only the
    # override that unlocks THAT guard.
    {
      has_domains: ['bin/ots domains remove', { domain_count: 1, domains: ['a.example.com'] }],
      drifted_domains: ['bin/ots domains doctor --all --repair',
                        { drifted_domains: ['ghost.example.com'] }],
      is_default: ['--force-default', { is_default: true }],
      active_subscription: ['--force-subscription', { active_subscription: true }],
      last_org: ['There is no override', { owner_org_count: 1 }],
    }.each do |status, (guidance, overrides)|
      it "exits 1 and points at the remediation for :#{status}" do
        allow(Onetime::Operations::Org::Delete).to receive(:new).and_return(
          instance_double(
            Onetime::Operations::Org::Delete,
            call: result_with(status: status, dry_run: false, **overrides),
          )
        )

        output = run_cli_command_quietly('org', 'delete', 'on_org_ext', '--yes')

        expect(last_exit_code).to eq(1)
        expect(output[:stdout]).to include(guidance)
      end
    end

    it 'names the drifted domains so the operator knows what doctor --repair targets' do
      allow(Onetime::Operations::Org::Delete).to receive(:new).and_return(
        instance_double(
          Onetime::Operations::Org::Delete,
          call: result_with(status: :drifted_domains, dry_run: false,
            drifted_domains: ['ghost.example.com']),
        )
      )

      output = run_cli_command_quietly('org', 'delete', 'on_org_ext', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('ghost.example.com')
    end

    it 'refuses at the plan pass without ever prompting' do
      allow(Onetime::Operations::Org::Delete).to receive(:new).and_return(
        instance_double(
          Onetime::Operations::Org::Delete,
          call: result_with(status: :is_default, dry_run: true, is_default: true),
        )
      )
      allow($stdin).to receive(:gets).and_return("y\n")

      output = run_cli_command_quietly('org', 'delete', 'on_org_ext')

      expect(last_exit_code).to eq(1)
      expect($stdin).not_to have_received(:gets)
      expect(output[:stdout]).to include('default (personal) workspace')
    end

    it 'exits 1 on a refusal in --json mode, with the status in the payload' do
      allow(Onetime::Operations::Org::Delete).to receive(:new).and_return(
        instance_double(
          Onetime::Operations::Org::Delete,
          call: result_with(status: :has_domains, dry_run: false, domain_count: 1,
            domains: ['a.example.com']),
        )
      )

      output = run_cli_command_quietly('org', 'delete', 'on_org_ext', '--yes', '--json')

      expect(last_exit_code).to eq(1)
      payload = JSON.parse(output[:stdout])
      expect(payload['status']).to eq('has_domains')
      expect(payload['domains']).to eq(['a.example.com'])
      expect(payload).to have_key('drifted_domains')
    end
  end

  describe 'applied output' do
    it 'reports the notification and repair counts' do
      output = run_cli_command_quietly('org', 'delete', 'on_org_ext', '--yes')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Deleted on_org_ext (Test Org)')
      expect(output[:stdout]).to include('members notified:    1/1')
      expect(output[:stdout]).to include('invitations revoked: 2')
      expect(output[:stdout]).to include('default_org_id cleared: ur_a')
    end

    it 'emits the full JSON payload under --yes --json' do
      output = run_cli_command_quietly('org', 'delete', 'on_org_ext', '--yes', '--json')

      payload = JSON.parse(output[:stdout])
      expect(payload).to include(
        'status' => 'success',
        'org_id' => 'on_org_ext',
        'planid' => 'free_v1',
        'members_notified' => 1,
        'pending_invitations' => 2,
        'dry_run' => false,
      )
    end
  end
end
