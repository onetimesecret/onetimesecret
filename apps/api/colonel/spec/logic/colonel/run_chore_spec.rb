# apps/api/colonel/spec/logic/colonel/run_chore_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/chores/:chore/run (#4343) — TIER 2: confirmation (the chore
# id) only, no elevation, no destructive budget, and a dry run is exempt. The op
# (limit, budget, dry-run rules, run record, audit) is covered in
# spec/unit/onetime/operations/chores/run_spec.rb; here it is a double.
RSpec.describe ColonelAPI::Logic::Colonel::RunChore do
  let(:chore) { 'housekeeping.organization.standardize_planid' }
  let(:run_class) { Onetime::Operations::Chores::Run }

  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_plain', extid: 'ur_plain',
      role: 'customer', verified?: true, anonymous?: false)
  end

  def op_result(**overrides)
    run_class::Result.new(
      status: :success, chore: chore, kind: 'housekeeping', dry_run: false, limit: 100,
      capped: false, budget_exhausted: false, duration_ms: 87,
      report: { 'model' => 'Onetime::Organization', 'scanned' => 12, 'modified' => 3, 'errors' => 0 },
      **overrides,
    )
  end

  let(:op) { instance_double(run_class, call: op_result) }

  def strategy_result_for(user, confirm_token)
    double('StrategyResult', session: {}, user: user,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(user = colonel, confirm_token = chore, params = {})
    described_class.new(strategy_result_for(user, confirm_token), { 'chore' => chore }.merge(params))
  end

  def processed(logic = logic_for)
    logic.raise_concerns
    logic.process
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime.billing_config).to receive(:enabled?).and_return(false)
    allow(run_class).to receive(:new).and_return(op)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  it 'declares the colonelChoreRun response schema' do
    expect(described_class::SCHEMAS).to eq(response: 'colonelChoreRun')
  end

  it 'is tier 2' do
    expect(ColonelAPI::DestructiveActions.tier2?(described_class)).to be true
  end

  describe 'confirmation (#4326)' do
    let(:expected_confirm_token) { chore }

    def confirmed_logic_for(confirm_token)
      logic_for(colonel, confirm_token)
    end

    it_behaves_like 'a confirmed colonel action'

    it 'runs nothing when the confirmation is refused' do
      expect { logic_for(colonel, nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(run_class).not_to have_received(:new)
    end
  end

  it 'does not charge the destructive budget (tier 2)' do
    logic = logic_for
    allow(logic).to receive(:enforce_colonel_destructive_limit!)

    logic.raise_concerns

    expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
  end

  it 'needs no confirmation for a dry run' do
    allow(op).to receive(:call).and_return(
      op_result(status: :dry_run, dry_run: true,
        report: { 'would_scan' => 12, 'total' => 12, 'dry_run_supported' => false }),
    )

    data = processed(logic_for(colonel, nil, 'dry_run' => true))

    expect(data[:record]).to include(status: 'dry_run', dry_run: true)
    expect(run_class).to have_received(:new).with(hash_including(dry_run: true))
  end

  describe 'guard order' do
    it 'rejects a non-colonel before anything else' do
      expect { logic_for(customer, nil, 'chore' => 'nope').raise_concerns }.to raise_error(Onetime::Forbidden)
    end

    it 'requires a chore id' do
      expect { logic_for(colonel, nil, 'chore' => '').raise_concerns }
        .to raise_error(Onetime::FormError, /Chore is required/)
    end

    it 'answers 404 for an unknown chore, BEFORE the confirmation gate' do
      expect { logic_for(colonel, nil, 'chore' => 'housekeeping.organization.no_such_chore').raise_concerns }
        .to raise_error(Onetime::RecordNotFound, /Unknown chore/)
    end

    it 'answers 404 for the excluded vhost cleanup, even with its id confirmed' do
      excluded = 'housekeeping.custom_domain.remove_orphaned_approximated_vhosts'

      expect { logic_for(colonel, excluded, 'chore' => excluded).raise_concerns }
        .to raise_error(Onetime::RecordNotFound, /Unknown chore/)
      expect(run_class).not_to have_received(:new)
    end

    it 'answers 404 for the entitlement run while billing is off' do
      expect { logic_for(colonel, 'entitlement_materialize', 'chore' => 'entitlement_materialize').raise_concerns }
        .to raise_error(Onetime::RecordNotFound)
    end

    it 'strips characters an id never has before the lookup' do
      logic = logic_for(colonel, chore, 'chore' => " Housekeeping.Organization.Standardize_Planid\n")

      expect { logic.raise_concerns }.not_to raise_error
      expect(logic.chore).to eq(chore)
    end

    [0, -1, 1_001, '1.5', 'abc', true].each do |bad|
      it "rejects limit #{bad.inspect} with 422 before the gate" do
        expect { logic_for(colonel, nil, 'limit' => bad).raise_concerns }
          .to raise_error(Onetime::FormError, /limit must be an integer between 1 and 1000/)
      end
    end

    it 'accepts the bounds and defaults a missing limit' do
      expect(logic_for(colonel, chore, 'limit' => 1_000).tap(&:raise_concerns).limit).to eq(1_000)
      expect(logic_for(colonel, chore, 'limit' => '1').tap(&:raise_concerns).limit).to eq(1)
      expect(logic_for.tap(&:raise_concerns).limit).to eq(100)
    end
  end

  describe 'process' do
    it 'hands the op the chore, the limit and the reason, with the public actor id' do
      processed(logic_for(colonel, chore, 'limit' => 250, 'reason' => 'cleanup after plan rename'))

      expect(run_class).to have_received(:new).with(
        chore: chore, actor: 'ur_colonel', dry_run: false, limit: 250, reason: 'cleanup after plan rename',
      )
    end

    it 'answers the contract shape' do
      expect(processed).to eq(
        record: {
          chore: chore, kind: 'housekeeping', status: 'success', dry_run: false, limit: 100,
          capped: false, budget_exhausted: false, duration_ms: 87,
        },
        details: {
          report: { 'model' => 'Onetime::Organization', 'scanned' => 12, 'modified' => 3, 'errors' => 0 },
          cli: 'bin/ots housekeeping run Onetime::Organization standardize_planid',
        },
      )
    end

    it 'passes a partial run through as reported' do
      allow(op).to receive(:call).and_return(op_result(capped: true, budget_exhausted: true))

      expect(processed[:record]).to include(capped: true, budget_exhausted: true)
    end
  end
end
