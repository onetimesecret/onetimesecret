# apps/api/colonel/spec/logic/colonel/create_organization_checkout_link_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

RSpec.describe ColonelAPI::Logic::Colonel::CreateOrganizationCheckoutLink do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', role: 'colonel',
      verified?: true, anonymous?: false)
  end

  let(:owner) do
    instance_double(Onetime::Customer,
      objid: 'cust_owner', extid: 'ur_owner', exists?: true, anonymous?: false)
  end

  let(:org) do
    instance_double(Onetime::Organization,
      objid: 'org_internal', extid: 'or_target', exists?: true, owner: owner)
  end

  let(:strategy_result) do
    double('StrategyResult', session: {}, user: colonel,
      auth_method: 'sessionauth', metadata: {})
  end

  let(:op_result) do
    Billing::Operations::CheckoutLinkResult.new(
      status: :created,
      url: 'https://checkout.stripe.com/c/pay/cs_test_123',
      session_id: 'cs_test_123',
      price_id: 'price_test_123',
      plan_id: 'identity_plus_v1',
      expires_at: 1_753_999_999,
      reason: nil,
    )
  end

  def logic_for(params = {})
    described_class.new(
      strategy_result,
      {
        'org_id' => 'or_target',
        'plan' => 'identity_plus_v1',
      }.merge(params),
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Onetime::Organization).to receive_messages(find_by_extid: org, load: nil)
    allow(Billing::Operations::CreateCheckoutLink).to receive(:call).and_return(op_result)
    allow(Onetime.billing_config).to receive(:region).and_return(nil)
  end

  it 'uses the resolved organization and its owner, not a default organization' do
    logic = logic_for('billing_cycle' => 'yearly', 'allow_promotion_codes' => 'true')
    logic.raise_concerns
    data = logic.process

    expect(Onetime::Organization).to have_received(:find_by_extid).with('or_target')
    expect(Billing::Operations::CreateCheckoutLink).to have_received(:call).with(
      customer: owner,
      org: org,
      product: 'identity_plus_v1',
      interval: 'yearly',
      actor: 'ur_colonel',
      allow_promotion_codes: true,
    )
    expect(data).to eq(
      record: {
        checkout_url: 'https://checkout.stripe.com/c/pay/cs_test_123',
        session_id: 'cs_test_123',
        plan_id: 'identity_plus_v1',
        price_id: 'price_test_123',
        expires_at: 1_753_999_999,
      },
      details: { region: 'global' },
    )
  end

  it 'falls back to objid after an extid miss' do
    allow(Onetime::Organization).to receive_messages(find_by_extid: nil, load: org)

    logic_for('org_id' => 'org_internal').raise_concerns

    expect(Onetime::Organization).to have_received(:load).with('org_internal')
  end

  it 'rejects an absent owner before creating a checkout link' do
    allow(org).to receive(:owner).and_return(nil)

    expect { logic_for.raise_concerns }
      .to raise_error(Onetime::RecordNotFound, /Organization owner not found/)
    expect(Billing::Operations::CreateCheckoutLink).not_to have_received(:call)
  end

  it 'rejects an owner record that no longer exists' do
    allow(owner).to receive(:exists?).and_return(false)

    expect { logic_for.raise_concerns }
      .to raise_error(Onetime::RecordNotFound, /Organization owner not found/)
    expect(Billing::Operations::CreateCheckoutLink).not_to have_received(:call)
  end

  it 'rejects an anonymous owner before creating a checkout link' do
    allow(owner).to receive(:anonymous?).and_return(true)

    expect { logic_for.raise_concerns }
      .to raise_error(Onetime::FormError, /anonymous organization owner/)
    expect(Billing::Operations::CreateCheckoutLink).not_to have_received(:call)
  end

  it 'rejects an invalid billing cycle' do
    expect { logic_for('billing_cycle' => 'fortnightly') }
      .to raise_error(Onetime::FormError, /Invalid billing cycle/)
  end
end
