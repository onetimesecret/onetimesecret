# apps/web/auth/spec/operations/ensure_default_workspace_collision_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'auth/operations/ensure_default_workspace'

RSpec.describe Auth::Operations::EnsureDefaultWorkspace do
  let(:email) { 'user@example.com' }
  let(:organizations) { double('organization_instances', count: 0) }
  let(:customer) do
    double(
      'Customer',
      email: email,
      custid: 'cust_current',
      extid: 'ur_current',
      organization_instances: organizations,
      provisioning_failure_code: nil,
      clear_provisioning_failure!: false,
      mark_provisioning_failed!: true,
    )
  end
  let(:organization) do
    double('Organization', objid: 'org_1', extid: 'on_1').tap do |org|
      allow(org).to receive(:is_default!).with(true)
    end
  end
  let(:classifier) { instance_double(Auth::Operations::WorkspaceCollision) }

  before do
    allow(Auth::Operations::WorkspaceCollision).to receive(:new).and_return(classifier)
    allow(Auth::Operations::WorkspaceCollision).to receive(:compare_and_delete).and_call_original
  end

  def collision(classification, organization: nil, raw: 'org_1')
    Auth::Operations::WorkspaceCollision::Result.new(
      classification: classification,
      email: email,
      organization: organization,
      raw_index_value: raw,
      evidence: { organization_extid: organization&.extid },
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
end
