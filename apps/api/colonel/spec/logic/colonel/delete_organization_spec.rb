# apps/api/colonel/spec/logic/colonel/delete_organization_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'
require 'onetime/operations/org/delete'

# Adapter-layer coverage only. The teardown, the guardrails and the single
# audit event live in Onetime::Operations::Org::Delete; the CLI adapter has its
# own spec. These examples assert what THIS adapter owns: the dry-run DEFAULT,
# the force-flag threading, the asymmetric status→HTTP mapping (a preview
# always answers 200; a refused APPLY is a 4xx), and that it records NO audit
# event of its own (CONTRACT 4 — the op owns the trail).
RSpec.describe ColonelAPI::Logic::Colonel::DeleteOrganization do
  let(:result_class) { Onetime::Operations::Org::Delete::Result }
  let(:op) { instance_double(Onetime::Operations::Org::Delete) }

  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', email: 'colonel@example.com',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:org) do
    instance_double(Onetime::Organization,
      objid: 'org_internal', extid: 'or_target', exists?: true)
  end

  let(:strategy_result) do
    double('StrategyResult', session: {}, user: colonel,
      auth_method: 'sessionauth', metadata: {})
  end

  def build_result(status:, **overrides)
    result_class.new(
      **{
        status: status,
        org_id: 'or_target',
        display_name: 'Target Org',
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
        dry_run: status == :planned,
      }.merge(overrides),
    )
  end

  # Builds the logic with the org param plus whatever the example is
  # exercising, and pins the op's answer. Callers still drive raise_concerns
  # (which resolves @org) before process, as the controller does.
  def logic_for(params = {}, status: :success, **result_overrides)
    allow(op).to receive(:call).and_return(build_result(status: status, **result_overrides))
    described_class.new(strategy_result, { 'org_id' => 'or_target' }.merge(params))
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Onetime::Organization).to receive(:find_by_extid).and_return(org)
    allow(Onetime::Operations::Org::Delete).to receive(:new).and_return(op)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  describe 'dry-run default (destructive verb, preview posture)' do
    it 'previews when no dry_run param is sent' do
      logic = logic_for({}, status: :planned)
      logic.raise_concerns
      data = logic.process

      expect(Onetime::Operations::Org::Delete).to have_received(:new)
        .with(hash_including(dry_run: true))
      expect(data[:record][:deleted]).to be false
      expect(data[:details][:dry_run]).to be true
    end

    it 'applies only when dry_run is explicitly falsy' do
      logic = logic_for({ 'dry_run' => 'false' })
      logic.raise_concerns
      data = logic.process

      expect(Onetime::Operations::Org::Delete).to have_received(:new)
        .with(hash_including(dry_run: false))
      expect(data[:record][:deleted]).to be true
    end
  end

  describe 'op invocation' do
    it 'hands the op the colonel extid as actor, never a synthesized identity' do
      logic = logic_for({ 'dry_run' => 'false' })
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Org::Delete).to have_received(:new)
        .with(hash_including(org: org, actor: 'ur_colonel', deleted_by: 'colonel@example.com'))
    end

    it 'defaults both force flags to false' do
      logic = logic_for({ 'dry_run' => 'false' })
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Org::Delete).to have_received(:new)
        .with(hash_including(force_default: false, force_subscription: false))
    end

    it 'threads each override through independently' do
      logic = logic_for({ 'dry_run' => 'false', 'force_default' => 'true' })
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Org::Delete).to have_received(:new)
        .with(hash_including(force_default: true, force_subscription: false))
    end

    it 'records no audit event of its own (the op owns the trail)' do
      logic = logic_for({ 'dry_run' => 'false' })
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe 'response shape' do
    it 'carries the plan the console builds its confirmation from' do
      logic = logic_for({}, status: :planned)
      logic.raise_concerns
      data = logic.process

      expect(data[:record]).to include(org_id: 'or_target', display_name: 'Target Org',
        status: 'planned')
      expect(data[:details][:members]).to eq([{ extid: 'ur_a', email: 'a@example.com' }])
      expect(data[:details][:pending_invitations]).to eq(2)
      expect(data[:details][:default_org_cleared]).to eq(['ur_a'])
      expect(data[:details][:owner_org_count]).to eq(2)
    end

    it 'reports deleted only on an applied success' do
      logic = logic_for({ 'dry_run' => 'false' })
      logic.raise_concerns

      expect(logic.process[:record][:deleted]).to be true
    end
  end

  describe 'status mapping — asymmetric by design' do
    # A PREVIEW is a report: it must carry the guardrail AND the plan, so the
    # console can explain the block and offer the override that clears it.
    [:has_domains, :is_default, :active_subscription, :last_org].each do |status|
      it "answers 200 with status #{status} on a dry run" do
        logic = logic_for({ 'dry_run' => 'true' }, status: status, dry_run: true)
        logic.raise_concerns
        data = logic.process

        expect(data[:record][:status]).to eq(status.to_s)
        expect(data[:record][:deleted]).to be false
      end
    end

    it 'raises a form error on an APPLY refused for domains, naming them' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :has_domains,
        domain_count: 1, domains: ['a.example.com'])
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |err|
        expect(err.message).to include('a.example.com')
      end
    end

    it 'raises a form error on an APPLY refused for a default workspace' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :is_default, is_default: true)
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError, /force_default=true/)
    end

    it 'raises a form error on an APPLY refused for an active subscription' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :active_subscription,
        active_subscription: true)
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError, /force_subscription=true/)
    end

    it 'raises a form error on :last_org and offers NO override' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :last_org, owner_org_count: 1)
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |err|
        expect(err.message).to include('no override')
        expect(err.message).not_to include('force_')
      end
    end

    it 'fails loudly on a status outside the adapter contract, never a 200' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :landed_partial)
      logic.raise_concerns

      expect { logic.process }
        .to raise_error(Onetime::Problem, /Unexpected delete status: landed_partial/)
    end

    it 'treats a leaked :planned on an apply as broken flag threading' do
      logic = logic_for({ 'dry_run' => 'false' }, status: :planned, dry_run: true)
      logic.raise_concerns

      expect { logic.process }
        .to raise_error(Onetime::Problem, /Unexpected delete status: planned/)
    end
  end

  describe 'resolution' do
    it 'raises not-found when the org does not resolve' do
      allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
      allow(Onetime::Organization).to receive(:load).and_return(nil)

      expect { logic_for.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end

    it 'requires an org_id param' do
      logic = logic_for({ 'org_id' => '' })

      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Organization ID is required/)
    end
  end
end
