# apps/web/billing/spec/cli/orgs_validate_command_spec.rb
#
# frozen_string_literal: true

require 'json'

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/orgs_validate_command'

RSpec.describe 'Billing Orgs Validate CLI', :billing_cli do
  subject(:command) { Onetime::CLI::BillingOrgsValidateCommand.new }

  let(:mock_instances) { instance_double(Familia::SortedSet) }

  def run_command(**kwargs)
    old_stdout = $stdout
    $stdout    = StringIO.new
    status     = nil
    begin
      command.call(**kwargs)
    rescue SystemExit => e
      status = e.status
    end
    [$stdout.string, status]
  ensure
    $stdout = old_stdout
  end

  def mock_org(extid:, planid:, display_name: 'Test Org', stripe_customer_id: '', stripe_subscription_id: '', subscription_status: '')
    instance_double(
      Onetime::Organization,
      extid: extid,
      planid: planid,
      display_name: display_name,
      stripe_customer_id: stripe_customer_id,
      stripe_subscription_id: stripe_subscription_id,
      subscription_status: subscription_status,
    )
  end

  before do
    allow(command).to receive(:boot_application!)
    allow(command).to receive(:billing_enabled?).and_return(true)
    allow(Onetime::Organization).to receive(:instances).and_return(mock_instances)
    allow(mock_instances).to receive(:element_count).and_return(0)
  end

  describe 'when all orgs have resolvable plan IDs' do
    let(:org_valid_stripe) { mock_org(extid: 'on_valid_a', planid: 'identity_plus_v1') }
    let(:org_valid_config) { mock_org(extid: 'on_valid_b', planid: 'free_v1') }
    let(:org_no_plan)      { mock_org(extid: 'on_empty', planid: '') }

    before do
      allow(mock_instances).to receive(:element_count).and_return(3)
      allow(mock_instances).to receive(:each_record)
        .and_yield(org_valid_stripe)
        .and_yield(org_valid_config)
        .and_yield(org_no_plan)

      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('identity_plus_v1')
        .and_return(plan: double, config: nil, source: 'stripe')

      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('free_v1')
        .and_return(plan: nil, config: {}, source: 'local_config')
    end

    it 'exits 0 and reports success' do
      output, status = run_command

      expect(status).to eq(0)
      expect(output).to include('Total orgs scanned:       3')
      expect(output).to include('Skipped (no planid):      1')
      expect(output).to include('Valid (Redis cache):      1')
      expect(output).to include('Valid (billing.yaml):     1')
      expect(output).to include('Invalid plan IDs:         0')
      expect(output).to include('All organizations have resolvable plan IDs.')
      expect(output).not_to include('INVALID PLAN IDS')
    end
  end

  describe 'when some orgs have unresolvable plan IDs' do
    let(:org_invalid_a) { mock_org(extid: 'on_a', planid: 'ghost_plan', display_name: 'Acme', subscription_status: 'active') }
    let(:org_invalid_b) { mock_org(extid: 'on_b', planid: 'ghost_plan', display_name: 'Beta') }
    let(:org_invalid_c) { mock_org(extid: 'on_c', planid: 'typo_plus_v1', display_name: '') }
    let(:org_valid)     { mock_org(extid: 'on_ok', planid: 'identity_plus_v1') }

    before do
      allow(mock_instances).to receive(:element_count).and_return(4)
      allow(mock_instances).to receive(:each_record)
        .and_yield(org_invalid_a)
        .and_yield(org_invalid_b)
        .and_yield(org_invalid_c)
        .and_yield(org_valid)

      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('ghost_plan')
        .and_return(plan: nil, config: nil, source: nil)

      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('typo_plus_v1')
        .and_return(plan: nil, config: nil, source: nil)

      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('identity_plus_v1')
        .and_return(plan: double, config: nil, source: 'stripe')
    end

    it 'exits 1 when invalid orgs are found' do
      _output, status = run_command

      expect(status).to eq(1)
    end

    it 'groups invalid orgs by planid, sorted by count descending' do
      output, _status = run_command

      expect(output).to include('Invalid plan IDs:         3')
      expect(output).to include('INVALID PLAN IDS')

      # ghost_plan appears before typo_plus_v1 because it has more orgs (2 vs 1)
      ghost_idx = output.index('ghost_plan (2 orgs)')
      typo_idx  = output.index('typo_plus_v1 (1 org)')
      expect(ghost_idx).not_to be_nil
      expect(typo_idx).not_to be_nil
      expect(ghost_idx).to be < typo_idx
    end

    it 'lists each invalid org under its planid heading' do
      output, _status = run_command

      expect(output).to include('on_a  Acme  [active]')
      expect(output).to include('on_b  Beta  [no sub]')
      expect(output).to include('on_c  (no name)  [no sub]')
    end

    it 'prints resolution hints' do
      output, _status = run_command

      expect(output).to include('Resolution:')
      expect(output).to include('bin/ots billing catalog pull')
      expect(output).to include('bin/ots billing diagnose --org')
    end

    it 'memoizes Plan.load_with_fallback per planid (no N+1)' do
      run_command

      # ghost_plan appears on two orgs; identity_plus_v1 and
      # typo_plus_v1 appear on one each. Without memoization we'd
      # see 4 calls; with memoization we see 3 (one per unique id).
      expect(::Billing::Plan).to have_received(:load_with_fallback).with('ghost_plan').once
      expect(::Billing::Plan).to have_received(:load_with_fallback).with('typo_plus_v1').once
      expect(::Billing::Plan).to have_received(:load_with_fallback).with('identity_plus_v1').once
    end
  end

  describe '--json output' do
    let(:org_invalid) { mock_org(extid: 'on_x', planid: 'ghost', display_name: 'Ghost Co', stripe_customer_id: 'cus_1', stripe_subscription_id: 'sub_1', subscription_status: 'canceled') }
    let(:org_valid)   { mock_org(extid: 'on_y', planid: 'identity_plus_v1') }

    before do
      allow(mock_instances).to receive(:element_count).and_return(2)
      allow(mock_instances).to receive(:each_record)
        .and_yield(org_invalid)
        .and_yield(org_valid)

      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('ghost')
        .and_return(plan: nil, config: nil, source: nil)

      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('identity_plus_v1')
        .and_return(plan: double, config: nil, source: 'stripe')
    end

    it 'emits valid JSON with stats and invalid orgs' do
      output, status = run_command(json: true)

      expect(status).to eq(1)
      parsed = JSON.parse(output)

      expect(parsed['stats']).to include(
        'total' => 2,
        'invalid' => 1,
        'valid_stripe' => 1,
      )

      expect(parsed['invalid_orgs'].size).to eq(1)
      expect(parsed['invalid_orgs'].first).to include(
        'extid' => 'on_x',
        'planid' => 'ghost',
        'display_name' => 'Ghost Co',
        'stripe_customer_id' => 'cus_1',
        'stripe_subscription_id' => 'sub_1',
        'subscription_status' => 'canceled',
      )

      expect(parsed['invalid_by_planid']).to have_key('ghost')
      expect(parsed['invalid_by_planid']['ghost'].size).to eq(1)
    end

    it 'suppresses the text report when --json is set' do
      output, _status = run_command(json: true)

      expect(output).not_to include('Organization Plan ID Validation')
      expect(output).not_to include('Resolution:')
    end
  end

  describe '--verbose output' do
    let(:org_invalid) { mock_org(extid: 'on_v', planid: 'ghost', subscription_status: 'past_due') }

    before do
      allow(mock_instances).to receive(:element_count).and_return(1)
      allow(mock_instances).to receive(:each_record).and_yield(org_invalid)
      allow(::Billing::Plan).to receive(:load_with_fallback)
        .with('ghost')
        .and_return(plan: nil, config: nil, source: nil)
    end

    it 'prints invalid orgs as they are detected' do
      output, _status = run_command(verbose: true)

      expect(output).to include('invalid: on_v  planid=ghost  sub=past_due')
    end

    it 'does not print per-org lines when --json is also set' do
      output, _status = run_command(verbose: true, json: true)

      expect(output).not_to include('invalid: on_v')
    end
  end

  describe 'when no organizations exist' do
    before do
      allow(mock_instances).to receive(:each_record)
    end

    it 'exits 0 with zero counts' do
      output, status = run_command

      expect(status).to eq(0)
      expect(output).to include('Total orgs scanned:       0')
      expect(output).to include('All organizations have resolvable plan IDs.')
    end
  end

  describe 'when billing is not enabled' do
    before do
      allow(command).to receive(:billing_enabled?).and_return(false)
      allow(mock_instances).to receive(:each_record)
    end

    it 'exits 0 without scanning organizations' do
      _output, status = run_command

      expect(status).to eq(0)
      expect(mock_instances).not_to have_received(:each_record)
    end
  end
end
