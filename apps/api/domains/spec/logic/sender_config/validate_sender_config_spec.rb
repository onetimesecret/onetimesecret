# apps/api/domains/spec/logic/sender_config/validate_sender_config_spec.rb
#
# frozen_string_literal: true

# Unit tests for SenderConfig::ValidateSenderConfig#raise_concerns (issue #4047).
#
# Regression guard: validation must be rejected up front when the mailer
# config has no provisioned DNS records. Without the guard, process would
# clear verification state and enqueue both workers with nothing to check —
# and DnsRecordCheckWorker's empty result set used to read as verified.
#
# RUN:
#   pnpm run test:rspec apps/api/domains/spec/logic/sender_config/validate_sender_config_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::SenderConfig::ValidateSenderConfig do
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

  let(:organization) do
    instance_double(Onetime::Organization, objid: 'org123', extid: 'ext-org123', display_name: 'Test Org')
  end

  let(:session) { { 'authenticated' => true, 'csrf' => 'test-csrf-token' } }
  let(:strategy_result) do
    double('StrategyResult', session: session, user: owner, authenticated?: true, metadata: {})
  end

  # The route is /:extid/email-config/validate, so the logic reads params['extid'].
  let(:params) { { 'extid' => 'ext-domain123' } }
  let(:logic) { described_class.new(strategy_result, params) }

  let(:from_address) { 'noreply@example.com' }
  let(:mailer_config) do
    instance_double(
      Onetime::CustomDomain::MailerConfig,
      from_address: from_address,
      provisioned?: provisioned,
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)

    # Bypass the (separately tested) authorization step; just set the ivars it
    # would populate so raise_concerns can proceed to the mailer_config checks.
    allow(logic).to receive(:authorize_sender_config!) do
      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@organization, organization)
    end
    allow(Onetime::CustomDomain::MailerConfig).to receive(:find_by_domain_id)
      .with('domain123').and_return(mailer_config)
  end

  context 'when the mailer config is not provisioned' do
    let(:provisioned) { false }

    it 'rejects validation with a form error before any state is touched' do
      expect { logic.raise_concerns }.to raise_error(OT::FormError) do |ex|
        expect(ex.message).to match(/provisioned/i)
        expect(ex.field).to eq(:domain_id)
        expect(ex.error_type).to eq(:invalid)
      end
    end
  end

  context 'when the mailer config is provisioned' do
    let(:provisioned) { true }

    it 'passes raise_concerns' do
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  context 'when from_address is missing' do
    let(:provisioned) { false }
    let(:from_address) { '' }

    it 'reports the missing from_address before the provisioned check' do
      expect { logic.raise_concerns }.to raise_error(OT::FormError) do |ex|
        expect(ex.field).to eq(:from_address)
        expect(ex.error_type).to eq(:missing)
      end
    end
  end

  context 'when no mailer config exists for the domain' do
    let(:mailer_config) { nil }

    it 'reports the missing sender configuration' do
      expect { logic.raise_concerns }.to raise_error(OT::FormError) do |ex|
        expect(ex.message).to match(/no sender configuration/i)
        expect(ex.field).to eq(:domain_id)
        expect(ex.error_type).to eq(:missing)
      end
    end
  end
end
