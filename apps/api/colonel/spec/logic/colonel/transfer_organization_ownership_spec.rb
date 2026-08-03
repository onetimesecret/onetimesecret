# apps/api/colonel/spec/logic/colonel/transfer_organization_ownership_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'
require 'onetime/operations/org/transfer_ownership'

# Adapter-layer coverage only. The transfer itself (promote-then-demote
# ordering, the owner_id pivot, rollback, and the single audit event) lives in
# Onetime::Operations::Org::TransferOwnership; the CLI adapter is covered by
# its own spec. These examples assert what THIS adapter owns: param handling
# and resolution, the pinned dry_run, status→HTTP mapping, and that it records
# NO audit event of its own (CONTRACT 4 — the op owns the trail).
RSpec.describe ColonelAPI::Logic::Colonel::TransferOrganizationOwnership do
  let(:result_class) { Onetime::Operations::Org::TransferOwnership::Result }
  let(:op) { instance_double(Onetime::Operations::Org::TransferOwnership) }

  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:org) do
    instance_double(Onetime::Organization,
      objid: 'org_internal', extid: 'or_target', exists?: true)
  end

  let(:new_owner) do
    instance_double(Onetime::Customer,
      objid: 'cust_new', extid: 'ur_newowner', anonymous?: false)
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
        from_owner_id: 'ur_oldowner',
        from_owner_role_after: 'admin',
        to_owner_id: 'ur_newowner',
        demoted: status == :success ? ['ur_oldowner'] : [],
        orphaned_owner: false,
        dry_run: false,
      }.merge(overrides),
    )
  end

  # Builds the logic with the two required params plus whatever the example is
  # exercising, and pins the op's answer. Callers still drive raise_concerns
  # (which resolves @org and @new_owner) before process, as the controller does.
  def logic_for(params = {}, status: :success, **result_overrides)
    allow(op).to receive(:call).and_return(build_result(status: status, **result_overrides))
    described_class.new(
      strategy_result,
      { 'org_id' => 'or_target', 'new_owner' => 'ur_newowner' }.merge(params),
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Onetime::Organization).to receive(:find_by_extid).and_return(org)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(new_owner)
    allow(Onetime::Operations::Org::TransferOwnership).to receive(:new).and_return(op)
    allow(Onetime::AdminAuditEvent).to receive(:record)
  end

  describe 'success path' do
    it 'returns the ack record with PUBLIC extids only' do
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(data[:record][:org_id]).to eq('or_target')
      expect(data[:record][:status]).to eq('success')
      expect(data[:record][:from_owner_id]).to eq('ur_oldowner')
      expect(data[:record][:to_owner_id]).to eq('ur_newowner')
      expect(data[:record][:demoted]).to eq(['ur_oldowner'])
      expect(data[:record][:demoted_to]).to eq('admin')
      expect(data[:record][:orphaned_owner]).to be false
    end

    it 'hands the op the colonel extid as actor, never a synthesized identity' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Org::TransferOwnership).to have_received(:new)
        .with(hash_including(org: org, new_owner: new_owner, actor: 'ur_colonel'))
    end

    it 'defaults demote_to to admin and threads an explicit value through downcased' do
      logic = logic_for
      logic.raise_concerns
      logic.process
      expect(Onetime::Operations::Org::TransferOwnership).to have_received(:new)
        .with(hash_including(demote_to: 'admin'))

      logic = logic_for({ 'demote_to' => 'Member' })
      logic.raise_concerns
      logic.process
      expect(Onetime::Operations::Org::TransferOwnership).to have_received(:new)
        .with(hash_including(demote_to: 'member'))
    end

    it 'records no audit event of its own (the op owns the trail)' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end

  describe 'dry_run pinned false (D12 — no preview flow in the console)' do
    it 'passes dry_run: false to the op' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Org::TransferOwnership).to have_received(:new)
        .with(hash_including(dry_run: false))
    end

    it 'ignores a dry_run param — there is no preview contract to honor' do
      logic = logic_for({ 'dry_run' => 'true' })
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Org::TransferOwnership).to have_received(:new)
        .with(hash_including(dry_run: false))
    end
  end

  describe 'status mapping' do
    it 'treats :no_change as an idempotent 200' do
      logic = logic_for(status: :no_change)
      logic.raise_concerns
      data = logic.process

      expect(data[:record][:status]).to eq('no_change')
      expect(data[:record][:demoted]).to eq([])
    end

    it 'raises a form error on :not_member with the add-first remediation' do
      logic = logic_for(status: :not_member)
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError, /not an active member/)
    end

    it 'raises a form error on :invalid_role naming the demotable roles' do
      logic = logic_for({ 'demote_to' => 'bogus' }, status: :invalid_role)
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |err|
        expect(err.message).to include('bogus')
        expect(err.message).to include(
          Onetime::Operations::Org::TransferOwnership::DEMOTABLE_ROLES.join(', '),
        )
      end
    end

    it 'fails loudly on a status outside the adapter contract, never a 200' do
      logic = logic_for(status: :landed_partial)
      logic.raise_concerns

      expect { logic.process }
        .to raise_error(Onetime::Problem, /Unexpected transfer status: landed_partial/)
    end

    it 'treats a leaked :planned as a broken dry_run pin, not a preview 200' do
      logic = logic_for(status: :planned, dry_run: true)
      logic.raise_concerns

      expect { logic.process }
        .to raise_error(Onetime::Problem, /Unexpected transfer status: planned/)
    end
  end

  describe 'resolution' do
    it 'raises not-found when the org does not resolve' do
      allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
      allow(Onetime::Organization).to receive(:load).and_return(nil)

      expect { logic_for.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end

    it 'raises not-found when the new owner does not resolve' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
      allow(Onetime::Customer).to receive(:load).and_return(nil)

      expect { logic_for.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end

    it 'requires a new_owner param' do
      logic = logic_for({ 'new_owner' => '' })

      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /New owner is required/)
    end
  end
end
