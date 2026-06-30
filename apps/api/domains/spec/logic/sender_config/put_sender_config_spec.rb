# apps/api/domains/spec/logic/sender_config/put_sender_config_spec.rb
#
# frozen_string_literal: true

# Unit tests for SenderConfig::PutSenderConfig#raise_concerns ordering.
#
# Regression: a blank from_address must be normalized to noreply@<domain>
# (via enforce_from_domain) BEFORE the required-field validation runs, so an
# operator with the custom_mail_sender entitlement can enable the sender
# without hand-typing an address. Previously validate_required_fields ran
# first and rejected the blank value before normalization could apply.
#
# RUN:
#   pnpm run test:rspec apps/api/domains/spec/logic/sender_config/put_sender_config_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::SenderConfig::PutSenderConfig do
  let(:owner) do
    instance_double(
      Onetime::Customer,
      custid: 'owner123',
      objid: 'owner123',
      extid: 'ext-owner123',
      anonymous?: false,
      verified?: true,
    )
  end

  let(:custom_domain) do
    instance_double(
      Onetime::CustomDomain,
      identifier: 'domain123',
      extid: 'ext-domain123',
      display_domain: 'example.com',
      org_id: 'org123',
    )
  end

  # flexible: whether the org holds the flexible_from_domain entitlement.
  def org_double(flexible:)
    org = instance_double(Onetime::Organization, objid: 'org123', extid: 'ext-org123', display_name: 'Test Org')
    allow(org).to receive(:can?).with('flexible_from_domain').and_return(flexible)
    org
  end

  let(:session) { { 'authenticated' => true, 'csrf' => 'test-csrf-token' } }
  let(:strategy_result) do
    double('StrategyResult', session: session, user: owner, authenticated?: true, metadata: {})
  end

  # The route is /:extid/email-config, so the logic reads params['extid'].
  let(:params) do
    { 'extid' => 'ext-domain123', 'from_name' => 'Acme', 'from_address' => from_address, 'enabled' => true }
  end
  let(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)

    # Bypass the (separately tested) authorization step; just set the ivars it
    # would populate so raise_concerns can proceed to enforce + validate.
    allow(logic).to receive(:authorize_sender_config!) do
      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@organization, organization)
    end
    allow(Onetime::CustomDomain::MailerConfig).to receive(:find_by_domain_id).and_return(nil)

    # Keep the test hermetic: we are asserting ordering, not Truemail/MX checks.
    allow(logic).to receive(:valid_email?).and_return(true)
    # process_params runs from Logic::Base#initialize, so @from_address/@domain_id
    # are already populated from params by the time raise_concerns is called.
  end

  context 'without the flexible_from_domain entitlement' do
    let(:organization) { org_double(flexible: false) }

    context 'when from_address is blank' do
      let(:from_address) { '' }

      it 'normalizes to noreply@<domain> instead of rejecting' do
        expect { logic.raise_concerns }.not_to raise_error
        expect(logic.instance_variable_get(:@from_address)).to eq('noreply@example.com')
      end
    end

    context 'when from_address has only a local part-ish value' do
      let(:from_address) { 'alerts' }

      it 'reattaches the custom domain' do
        logic.raise_concerns
        expect(logic.instance_variable_get(:@from_address)).to eq('alerts@example.com')
      end
    end

    context 'when a full from_address is provided' do
      let(:from_address) { 'hello@example.com' }

      it 'keeps the local part and enforces the domain' do
        logic.raise_concerns
        expect(logic.instance_variable_get(:@from_address)).to eq('hello@example.com')
      end
    end
  end

  context 'with the flexible_from_domain entitlement' do
    let(:organization) { org_double(flexible: true) }

    context 'when from_address is blank' do
      let(:from_address) { '' }

      it 'still requires an explicit address (no domain to default to)' do
        expect { logic.raise_concerns }.to raise_error(/from address is required/i)
      end
    end

    context 'when a from_address on another domain is provided' do
      let(:from_address) { 'team@other.test' }

      it 'is left unchanged (flexible mode)' do
        logic.raise_concerns
        expect(logic.instance_variable_get(:@from_address)).to eq('team@other.test')
      end
    end
  end
end
