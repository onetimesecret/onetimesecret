# apps/web/auth/spec/operations/ensure_default_workspace_collision_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'auth/operations/ensure_default_workspace'

RSpec.describe Auth::Operations::EnsureDefaultWorkspace do
  let(:email) { 'user@example.com' }
  let(:organizations) { double('organization_instances', count: 0, to_a: []) }
  let(:customer) do
    double(
      'Customer',
      email: email,
      custid: 'cust_current',
      objid: 'cust_current',
      extid: 'ur_current',
      organization_instances: organizations,
      provisioning_failure_code: nil,
      clear_provisioning_failure!: false,
      mark_provisioning_failed!: true,
    )
  end
  let(:organization) do
    double('Organization', objid: 'org_1', extid: 'on_1', is_default: true).tap do |org|
      allow(org).to receive(:is_default!).with(true)
    end
  end
  let(:classifier) { instance_double(Auth::Operations::WorkspaceCollision) }
  # The per-customer creation lock, shared with CreateOrganization.
  let(:lock) { instance_double(Familia::Lock) }
  let(:lock_token) { 'lock-token-abc123' }

  before do
    allow(Familia::Lock).to receive(:new).and_return(lock)
    allow(lock).to receive(:acquire).and_return(lock_token)
    allow(lock).to receive(:release).and_return(true)
    allow(Auth::Operations::WorkspaceCollision).to receive(:new).and_return(classifier)
    allow(Auth::Operations::WorkspaceCollision).to receive(:compare_and_delete).and_call_original
    # Keep the contender's bounded wait short; the loop shape is what is under test.
    stub_const('Auth::Operations::EnsureDefaultWorkspace::CREATE_LOCK_WAIT', 0.2)
    stub_const('Auth::Operations::EnsureDefaultWorkspace::CREATE_LOCK_INTERVAL', 0.01)
  end

  def collision(classification, organization: nil, raw: 'org_1', evidence: {})
    Auth::Operations::WorkspaceCollision::Result.new(
      classification: classification,
      email: email,
      organization: organization,
      raw_index_value: raw,
      evidence: { organization_extid: organization&.extid }.merge(evidence),
    )
  end

  def operation
    described_class.new(customer: customer).tap do |op|
      allow(op).to receive(:apply_pending_federation!).and_return(false)
    end
  end

  it 'converges on a valid workspace already owned by the current customer' do
    allow(Onetime::Organization).to receive(:create!).and_raise(Onetime::OrganizationExists)
    allow(classifier).to receive(:call).and_return(
      collision(:current_valid_workspace, organization: organization),
    )

    result = operation.call

    expect(result[:organization]).to be(organization)
    expect(organization).not_to have_received(:is_default!)
  end

  it 'compare-and-deletes a proven phantom claim and retries creation once' do
    allow(Onetime::Organization).to receive(:create!).and_invoke(
      ->(*) { raise Onetime::OrganizationExists },
      ->(*) { organization },
    )
    phantom = collision(:phantom_index)
    allow(classifier).to receive(:call).and_return(phantom)
    allow(Auth::Operations::WorkspaceCollision).to receive(:compare_and_delete)
      .with(phantom).and_return(true)

    result = operation.call

    expect(result[:organization]).to be(organization)
    expect(Onetime::Organization).to have_received(:create!).twice
    expect(organization).to have_received(:is_default!).with(true)
  end

  it 'surfaces a classified collision instead of adopting an empty orphan by email' do
    allow(Onetime::Organization).to receive(:create!).and_raise(Onetime::OrganizationExists)
    orphan = collision(:empty_orphan, organization: organization)
    allow(classifier).to receive(:call).and_return(orphan)

    expect { operation.call }
      .to raise_error(Auth::Operations::WorkspaceCollision::ProvisioningCollision) do |error|
        expect(error.collision.classification).to eq(:empty_orphan)
      end
    expect(customer).to have_received(:mark_provisioning_failed!).with(
      code: 'default_workspace_collision',
      classification: :empty_orphan,
    )
  end

  it 'does not let stale-member cleanup enable adoption' do
    allow(Onetime::Organization).to receive(:create!).and_raise(Onetime::OrganizationExists)
    stale = collision(:stale_members, organization: organization)
    allow(classifier).to receive(:call).and_return(stale)

    expect { operation.call }
      .to raise_error(Auth::Operations::WorkspaceCollision::ProvisioningCollision)
    expect(Auth::Operations::WorkspaceCollision).not_to have_received(:compare_and_delete)
  end

  it 'clears a persisted failure after successful provisioning' do
    allow(Onetime::Organization).to receive(:create!).and_return(organization)

    result = operation.call

    expect(result[:organization]).to be(organization)
    expect(customer).to have_received(:clear_provisioning_failure!)
  end

  describe 'unreadable collision evidence' do
    it 'fails retryable without latching, and the next call proceeds once classification succeeds' do
      allow(Onetime::Organization).to receive(:create!).and_invoke(
        ->(*) { raise Onetime::OrganizationExists },
        ->(*) { raise Onetime::OrganizationExists },
      )
      allow(classifier).to receive(:call).and_return(
        collision(:unreadable, evidence: { error: 'Redis::TimeoutError', reason: 'timed out' }),
        collision(:current_valid_workspace, organization: organization),
      )

      expect { operation.call }
        .to raise_error(Onetime::AccountProvisioningUnavailable) do |error|
          expect(error.reason).to eq(:collision_unreadable)
          expect(error.collision.classification).to eq(:unreadable)
          expect(error.to_h).to include(error_type: 'AccountProvisioningUnavailable', reason: :collision_unreadable)
        end
      expect(customer).not_to have_received(:mark_provisioning_failed!)

      expect(operation.call[:organization]).to be(organization)
      expect(customer).not_to have_received(:mark_provisioning_failed!)
    end
  end

  describe 'per-customer creation lock' do
    it 'takes the org-creation lock CreateOrganization uses, with a TTL, and releases it after creating' do
      allow(Onetime::Organization).to receive(:create!).and_return(organization)

      operation.call

      # Literal AND shared definition: the literal pins the wire key that
      # CreateOrganization's lock lives under, the method pins that this call
      # site goes through the shared definition rather than its own string.
      expect(Familia::Lock).to have_received(:new).with('customer:cust_current:org_creation_lock')
      expect(Familia::Lock).to have_received(:new).with(Onetime::Customer.org_creation_lock_key('cust_current'))
      expect(lock).to have_received(:acquire).with(ttl: described_class::CREATE_LOCK_TTL)
      expect(lock).to have_received(:release).with(lock_token)
    end

    it 'releases the lock when creation raises' do
      allow(Onetime::Organization).to receive(:create!).and_raise(Onetime::OrganizationExists)
      allow(classifier).to receive(:call).and_return(collision(:retained_data, organization: organization))

      expect { operation.call }.to raise_error(Auth::Operations::WorkspaceCollision::ProvisioningCollision)
      expect(lock).to have_received(:release).once.with(lock_token)
    end

    it 'does not create when the previous holder provisioned between the first check and the lock' do
      allow(Onetime::Organization).to receive(:create!)
      allow(organizations).to receive(:count).and_return(0, 1)

      expect(operation.call).to be_nil
      expect(Onetime::Organization).not_to have_received(:create!)
      expect(customer).to have_received(:clear_provisioning_failure!)
    end

    context 'when another request holds the lock' do
      before do
        allow(lock).to receive(:acquire).and_return(false)
        allow(classifier).to receive(:call)
      end

      it 'waits for that workspace and returns it without creating, classifying, or latching' do
        allow(Onetime::Organization).to receive(:create!)
        allow(organizations).to receive(:count).and_return(0, 0, 0, 1)
        allow(organizations).to receive(:to_a).and_return([organization])

        result = operation.call

        expect(result[:organization]).to be(organization)
        expect(Onetime::Organization).not_to have_received(:create!)
        expect(classifier).not_to have_received(:call)
        expect(customer).not_to have_received(:mark_provisioning_failed!)
        expect(customer).to have_received(:clear_provisioning_failure!)
        expect(lock).not_to have_received(:release)
      end

      it 'fails retryable without latching when nothing appears within the wait' do
        allow(Onetime::Organization).to receive(:create!)

        expect { operation.call }
          .to raise_error(Onetime::AccountProvisioningUnavailable) do |error|
            expect(error.reason).to eq(:provisioning_in_progress)
          end
        expect(Onetime::Organization).not_to have_received(:create!)
        expect(classifier).not_to have_received(:call)
        expect(customer).not_to have_received(:mark_provisioning_failed!)
      end

      it 'polls the workspace at debug so a contended request keeps one info line' do
        logger = double('auth_logger', info: nil, debug: nil, warn: nil, error: nil)
        op     = operation
        allow(op).to receive(:auth_logger).and_return(logger)

        expect { op.call }.to raise_error(Onetime::AccountProvisioningUnavailable)

        # One info read before the lock attempt; every poll-loop read after
        # that is debug, or a contended request would log ~20 info lines.
        expect(logger).to have_received(:info).with(/has 0 organizations/).once
        expect(logger).to have_received(:debug).with(/has 0 organizations/).at_least(:twice)
      end
    end
  end
end
