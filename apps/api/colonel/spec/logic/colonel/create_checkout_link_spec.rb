# apps/api/colonel/spec/logic/colonel/create_checkout_link_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# Adapter-layer coverage only. Session creation itself is covered by
# apps/web/billing/spec/operations/create_checkout_link_spec.rb. These
# examples assert what THIS adapter owns: identifier/param handling, customer
# and org resolution, failure translation, and the frozen record/details
# envelope the frontend builds against.
RSpec.describe ColonelAPI::Logic::Colonel::CreateCheckoutLink do
  let(:colonel) do
    instance_double(
      Onetime::Customer,
      objid: 'cust_colonel',
      extid: 'ur_colonel',
      role: 'colonel',
      verified?: true,
      anonymous?: false,
    )
  end

  let(:target) do
    instance_double(
      Onetime::Customer,
      objid: 'cust_target',
      extid: 'ur_target',
      email: 'user@example.com',
      exists?: true,
      anonymous?: false,
    )
  end

  let(:org) { instance_double(Onetime::Organization, objid: 'org_obj_1', extid: 'org_ext_1') }

  let(:strategy_result) do
    double(
      'StrategyResult',
      session: {},
      user: colonel,
      auth_method: 'sessionauth',
      metadata: {},
    )
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
      { 'user_id' => 'user@example.com', 'plan' => 'identity_plus_v1' }.merge(params),
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Onetime::Customer).to receive_messages(load_by_extid_or_email: target, load: nil)
    allow(Billing::Operations::CreateCheckoutLink).to receive_messages(
      default_org_for: org,
      call: op_result,
    )
    allow(Onetime.billing_config).to receive(:region).and_return('EU')
  end

  it 'creates a link and emits the frozen record/details envelope' do
    logic = logic_for('enable_tax' => 'true', 'allow_promotion_codes' => 'true')
    logic.raise_concerns
    data  = logic.process

    expect(Billing::Operations::CreateCheckoutLink).to have_received(:call).with(
      customer: target,
      org: org,
      product: 'identity_plus_v1',
      interval: 'monthly',
      actor: 'ur_colonel',
      enable_tax: true,
      allow_promotion_codes: true,
    )
    expect(data[:record]).to eq(
      checkout_url: 'https://checkout.stripe.com/c/pay/cs_test_123',
      session_id: 'cs_test_123',
      plan_id: 'identity_plus_v1',
      price_id: 'price_test_123',
      expires_at: 1_753_999_999,
    )
    expect(data[:details]).to eq(region: 'EU', tax_enabled: true)
  end

  it 'resolves an email identifier without mangling it (sanitize_account_identifier)' do
    logic = logic_for
    logic.raise_concerns

    expect(Onetime::Customer).to have_received(:load_by_extid_or_email).with('user@example.com')
  end

  it 'defaults billing_cycle to monthly and booleans to false' do
    logic = logic_for
    logic.raise_concerns
    logic.process

    expect(Billing::Operations::CreateCheckoutLink).to have_received(:call).with(
      hash_including(interval: 'monthly', enable_tax: false, allow_promotion_codes: false),
    )
  end

  it 'accepts yearly billing_cycle' do
    logic = logic_for('billing_cycle' => 'yearly')
    logic.raise_concerns
    logic.process

    expect(Billing::Operations::CreateCheckoutLink).to have_received(:call).with(
      hash_including(interval: 'yearly'),
    )
  end

  it 'rejects a garbage billing_cycle' do
    expect { logic_for('billing_cycle' => 'fortnightly') }
      .to raise_error(Onetime::FormError, /Invalid billing cycle/)
  end

  it '404s when the identifier resolves to no customer' do
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)

    expect { logic_for.raise_concerns }
      .to raise_error(Onetime::RecordNotFound, /User not found/)
  end

  it '404s when the customer has no organization' do
    allow(Billing::Operations::CreateCheckoutLink).to receive(:default_org_for).and_return(nil)

    expect { logic_for.raise_concerns }
      .to raise_error(Onetime::RecordNotFound, /no organization/)
  end

  it 'translates an op failure into a form error with the reason' do
    failed = Billing::Operations::CheckoutLinkResult.new(
      status: :failed, url: nil, session_id: nil, price_id: nil,
      plan_id: nil, expires_at: nil, reason: 'Plan not found: bogus_v1',
    )
    allow(Billing::Operations::CreateCheckoutLink).to receive(:call).and_return(failed)

    logic = logic_for
    logic.raise_concerns

    expect { logic.process }.to raise_error(Onetime::FormError, /Plan not found: bogus_v1/)
  end
end
