# spec/cli/org_entitlement_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots org entitlement …` (#3731).
#
# Covers the dry-cli three-level registration guard (D16), the landing command,
# resolution, the --yes / --json refusal, the interactive decline, the
# standalone dead-letter warning (D17) and the op-status -> exit-code mapping.
# The mutation itself is the op's job and is covered by
# spec/unit/onetime/operations/org/entitlement_override_spec.rb — here the op is
# stubbed at its constructor so these stay pure adapter tests.
#
# Kept in its own file rather than appended to spec/cli/org_command_spec.rb
# because that file is owned by the `org reconcile` change landing in parallel.
#
# Run: bundle exec rspec spec/cli/org_entitlement_command_spec.rb

require_relative 'cli_spec_helper'

# lib/onetime/cli/ is NOT auto-discovered; these are also listed in the
# lib/onetime/cli.rb manifest. Required here so the spec is independent of
# manifest ordering.
require 'onetime/cli/org/shared'
require 'onetime/cli/org/entitlement_command'
require 'onetime/cli/org/entitlement_grant_command'
require 'onetime/cli/org/entitlement_revoke_command'
require 'onetime/cli/org/entitlement_clear_command'
require 'onetime/cli/org/entitlement_show_command'

RSpec.describe 'Org Entitlement Command', type: :cli do
  let(:billing_enabled) { true }

  let(:organization) do
    double(
      'Organization',
      objid: 'org-obj-1',
      extid: 'on_org_ext',
      display_name: 'Test Org',
      billing_enabled?: billing_enabled,
    )
  end

  let(:result) do
    Onetime::Operations::Org::EntitlementOverride::Result.new(
      status: :granted,
      org_id: 'on_org_ext',
      action: 'grant',
      entitlement: 'custom_branding',
      effective: %w[api_access create_secrets custom_branding],
      grants: ['custom_branding'],
      revokes: [],
      standalone: false,
      dry_run: false,
    )
  end

  let(:operation) do
    instance_double(Onetime::Operations::Org::EntitlementOverride, call: result)
  end

  before do
    allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(organization)
    allow(Onetime::Organization).to receive(:load).and_return(nil)
    allow(Onetime::Operations::Org::EntitlementOverride).to receive(:new).and_return(operation)
    # Adapter-side catalog warning: default to "known" so only the example that
    # exercises the warning has to think about it.
    allow(Onetime::Operations::Org::EntitlementOverride)
      .to receive(:known_entitlement?).and_return(true)
  end

  # D16 / the dry-cli trap: `org entitlement grant` is THREE levels under a
  # registered parent. Without a command object on the `org entitlement` node,
  # dry-cli's help walks a nil intermediate and `bin/ots org --help` blows up.
  describe 'three-level registration (D16 regression guard)' do
    it 'renders `org --help` without crashing' do
      output = run_cli_command_quietly('org', '--help')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('entitlement')
    end

    it 'renders `org entitlement --help` and lists the verbs' do
      output = run_cli_command_quietly('org', 'entitlement', '--help')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('grant')
      expect(output[:stdout]).to include('revoke')
      expect(output[:stdout]).to include('clear')
      expect(output[:stdout]).to include('show')
    end

    it 'prints usage and exits 0 for the bare landing command' do
      output = run_cli_command_quietly('org', 'entitlement')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('bin/ots org entitlement grant ORG ENT')
      expect(output[:stdout]).to include('bin/ots org entitlement show ORG')
    end
  end

  describe 'grant' do
    it 'exits 1 when the organization cannot be resolved' do
      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'nope', 'custom_branding', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Organization not found: nope')
      expect(Onetime::Operations::Org::EntitlementOverride).not_to have_received(:new)
    end

    it 'calls the op with the shared CLI sentinel actor, never a Customer' do
      run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding', '--yes')

      expect(Onetime::Operations::Org::EntitlementOverride).to have_received(:new).with(
        org: organization,
        action: 'grant',
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        entitlement: 'custom_branding',
        dry_run: false,
      )
    end

    it 'refuses to apply without --yes in --json mode' do
      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])['error'])
        .to eq('Refusing to grant entitlement overrides without --yes in --json mode')
      expect(Onetime::Operations::Org::EntitlementOverride).not_to have_received(:new)
    end

    it 'aborts without calling the op when the confirmation is declined' do
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Aborted.')
      expect(Onetime::Operations::Org::EntitlementOverride).not_to have_received(:new)
    end

    it 'applies after an interactive confirmation' do
      allow($stdin).to receive(:gets).and_return("y\n")

      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding')

      expect(output[:stdout]).to include("Grant 'custom_branding' to on_org_ext (Test Org)?")
      expect(Onetime::Operations::Org::EntitlementOverride).to have_received(:new)
    end

    it 'passes dry_run: true for --dry-run and needs no confirmation' do
      run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding', '--dry-run')

      expect(Onetime::Operations::Org::EntitlementOverride).to have_received(:new)
        .with(hash_including(dry_run: true))
    end

    it 'prints the resulting override sets on the text path' do
      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding', '--yes')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Status:       granted')
      expect(output[:stdout]).to include('Grants (1):')
      expect(output[:stdout]).to include('- custom_branding')
      expect(output[:stdout]).to include('Revokes (0):')
    end

    it 'emits the flat Result payload and exits 0 on --json --yes' do
      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding', '--yes', '--json')

      payload = JSON.parse(output[:stdout])
      expect(last_exit_code).to eq(0)
      expect(payload['status']).to eq('granted')
      expect(payload['org_id']).to eq('on_org_ext')
      expect(payload['action']).to eq('grant')
      expect(payload['entitlement']).to eq('custom_branding')
      expect(payload['grants']).to eq(['custom_branding'])
      expect(payload['standalone']).to be(false)
    end

    it 'exits 0 on the idempotent :no_change status' do
      allow(operation).to receive(:call).and_return(result.with(status: :no_change))

      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding', '--yes', '--json')

      expect(last_exit_code).to eq(0)
      expect(JSON.parse(output[:stdout])['status']).to eq('no_change')
    end

    it 'exits 1 when the op refuses the input' do
      allow(operation).to receive(:call)
        .and_return(result.with(status: :missing_entitlement, effective: nil, grants: nil, revokes: nil))

      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding', '--yes')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Entitlement is required for grant/revoke')
    end
  end

  # D17: the loudest line the CLI has. On a billing-disabled install the write
  # is a dead letter and `entitlement show` will still display it.
  describe 'standalone advisory (D17)' do
    let(:billing_enabled) { false }

    it 'warns on STDERR before the op runs, and still applies' do
      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding', '--yes')

      expect(output[:stderr]).to include('BILLING IS DISABLED ON THIS INSTALL')
      expect(output[:stderr]).to include('DEAD LETTER')
      expect(Onetime::Operations::Org::EntitlementOverride).to have_received(:new)
    end

    it 'keeps STDOUT parseable in --json mode (advisories never contaminate it)' do
      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding', '--yes', '--json')

      expect { JSON.parse(output[:stdout]) }.not_to raise_error
      expect(output[:stderr]).to include('BILLING IS DISABLED ON THIS INSTALL')
    end
  end

  describe 'unknown-entitlement advisory (warn, never block)' do
    it 'warns on STDERR and still calls the op' do
      allow(Onetime::Operations::Org::EntitlementOverride)
        .to receive(:known_entitlement?).with('future_feature_xyz').and_return(false)

      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'future_feature_xyz', '--yes')

      expect(output[:stderr]).to include("'future_feature_xyz' is not in the billing catalog")
      expect(Onetime::Operations::Org::EntitlementOverride).to have_received(:new)
    end

    it 'warns that an org grant does not reach a member outside the role template' do
      output = run_cli_command_quietly('org', 'entitlement', 'grant', 'on_org_ext', 'custom_branding', '--yes')

      expect(output[:stderr]).to include('Org scope is not member scope')
    end
  end

  describe 'revoke' do
    let(:result) do
      Onetime::Operations::Org::EntitlementOverride::Result.new(
        status: :revoked, org_id: 'on_org_ext', action: 'revoke', entitlement: 'api_access',
        effective: ['create_secrets'], grants: [], revokes: ['api_access'],
        standalone: false, dry_run: false
      )
    end

    it 'calls the op with action revoke' do
      run_cli_command_quietly('org', 'entitlement', 'revoke', 'on_org_ext', 'api_access', '--yes')

      expect(Onetime::Operations::Org::EntitlementOverride).to have_received(:new)
        .with(hash_including(action: 'revoke', entitlement: 'api_access', dry_run: false))
    end

    it 'does NOT print the role-scope advisory (that is a grant concern)' do
      output = run_cli_command_quietly('org', 'entitlement', 'revoke', 'on_org_ext', 'api_access', '--yes')

      expect(output[:stderr]).not_to include('Org scope is not member scope')
    end

    it 'prompts with revoke wording' do
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('org', 'entitlement', 'revoke', 'on_org_ext', 'api_access')

      expect(output[:stdout]).to include("Revoke 'api_access' from on_org_ext (Test Org)?")
    end
  end

  describe 'clear' do
    let(:result) do
      Onetime::Operations::Org::EntitlementOverride::Result.new(
        status: :cleared, org_id: 'on_org_ext', action: 'clear', entitlement: nil,
        effective: %w[api_access create_secrets], grants: [], revokes: [],
        standalone: false, dry_run: false
      )
    end

    it 'takes no ENTITLEMENT argument and calls the op with entitlement: nil' do
      run_cli_command_quietly('org', 'entitlement', 'clear', 'on_org_ext', '--yes')

      expect(Onetime::Operations::Org::EntitlementOverride).to have_received(:new)
        .with(hash_including(action: 'clear', entitlement: nil, dry_run: false))
    end

    it 'refuses to wipe overrides without --yes in --json mode' do
      output = run_cli_command_quietly('org', 'entitlement', 'clear', 'on_org_ext', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])['error'])
        .to eq('Refusing to clear entitlement overrides without --yes in --json mode')
      expect(Onetime::Operations::Org::EntitlementOverride).not_to have_received(:new)
    end

    it 'prompts with the destructive wording and aborts on a decline' do
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('org', 'entitlement', 'clear', 'on_org_ext')

      expect(output[:stdout]).to include('Clear ALL entitlement overrides (every grant AND revoke)')
      expect(output[:stdout]).to include('Aborted.')
      expect(Onetime::Operations::Org::EntitlementOverride).not_to have_received(:new)
    end

    it 'renders "(all overrides)" rather than a blank entitlement line' do
      output = run_cli_command_quietly('org', 'entitlement', 'clear', 'on_org_ext', '--yes')

      expect(output[:stdout]).to include('Entitlement:  (all overrides)')
      expect(last_exit_code).to eq(0)
    end
  end

  # `show` is read-only and calls NO op — it is a projection of model state
  # (D20). Stub the collections the report reads.
  describe 'show' do
    let(:organization) do
      double(
        'Organization',
        objid: 'org-obj-1',
        extid: 'on_org_ext',
        display_name: 'Test Org',
        planid: 'identity_plus_v1',
        billing_enabled?: billing_enabled,
        entitlements_plan: double('PlanSet', to_a: %w[create_secrets api_access]),
        entitlements_grants: double('GrantsSet', to_a: ['custom_branding']),
        entitlements_revokes: double('RevokesSet', to_a: ['api_access']),
        materialized_entitlements: double('MaterializedSet', to_a: %w[create_secrets custom_branding]),
        materialized_entitlements_at_parsed: { timestamp: 1_750_000_000, content_hash: 'abc' },
        entitlements_materialized?: true,
        # Plan-definition staleness is a separate axis from override drift; it
        # is reported, not asserted on, in most examples.
        entitlements_stale?: false,
      )
    end

    it 'reports plan / grants / revokes / expected / materialized and no drift' do
      output = run_cli_command_quietly('org', 'entitlement', 'show', 'on_org_ext')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Organization: on_org_ext (Test Org)')
      expect(output[:stdout]).to include('Plan:         identity_plus_v1')
      expect(output[:stdout]).to include('Override grants (1):')
      expect(output[:stdout]).to include('Override revokes (1):')
      expect(output[:stdout]).to include('Drift: none')
      expect(Onetime::Operations::Org::EntitlementOverride).not_to have_received(:new)
    end

    it 'reports drift when materialized disagrees with plan + grants - revokes' do
      allow(organization).to receive(:materialized_entitlements)
        .and_return(double('MaterializedSet', to_a: %w[create_secrets api_access orphan_ent]))

      output = run_cli_command_quietly('org', 'entitlement', 'show', 'on_org_ext')

      expect(output[:stdout]).to include('+ orphan_ent')
      expect(output[:stdout]).to include('- custom_branding')
      expect(output[:stdout]).to include('bin/ots org reconcile on_org_ext --yes')
    end

    it 'emits the whole report as JSON with --json' do
      output = run_cli_command_quietly('org', 'entitlement', 'show', 'on_org_ext', '--json')

      payload = JSON.parse(output[:stdout])
      expect(payload['org_id']).to eq('on_org_ext')
      expect(payload['grants']).to eq(['custom_branding'])
      expect(payload['expected']).to eq(%w[create_secrets custom_branding])
      expect(payload['drift']['in_sync']).to be(true)
    end

    context 'on a standalone install' do
      let(:billing_enabled) { false }

      it 'warns that the report describes stored state, not enforced state' do
        output = run_cli_command_quietly('org', 'entitlement', 'show', 'on_org_ext')

        expect(output[:stderr]).to include('Billing is DISABLED on this install')
        expect(output[:stderr]).to include('not what the application actually enforces')
      end
    end
  end
end
