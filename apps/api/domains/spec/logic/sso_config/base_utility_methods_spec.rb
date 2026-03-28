# apps/api/domains/spec/logic/sso_config/base_utility_methods_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::SsoConfig::Base do
  # Test through a concrete subclass since Base is abstract
  let(:described_logic_class) { DomainsAPI::Logic::SsoConfig::GetSsoConfig }

  let(:owner) do
    instance_double(
      Onetime::Customer,
      custid: 'owner123',
      objid: 'owner123',
      extid: 'ext-owner123',
      anonymous?: false,
    )
  end

  let(:session) do
    {
      'authenticated' => true,
      'csrf' => 'test-csrf-token',
    }
  end

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: owner,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:params) { { 'domain_id' => 'ext-domain123' } }
  let(:logic) { described_logic_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(OT).to receive(:now).and_return(Time.now.to_i)
  end

  describe '#parse_allowed_domains' do
    subject(:parse) { logic.send(:parse_allowed_domains, value) }

    context 'with nil' do
      let(:value) { nil }

      it { is_expected.to eq([]) }
    end

    context 'with empty string' do
      let(:value) { '' }

      it { is_expected.to eq([]) }
    end

    context 'with single domain' do
      let(:value) { 'example.com' }

      it { is_expected.to eq(['example.com']) }
    end

    context 'with comma-separated domains' do
      let(:value) { 'example.com, test.org' }

      it { is_expected.to eq(['example.com', 'test.org']) }
    end

    context 'with whitespace and mixed case' do
      let(:value) { '  EXAMPLE.COM , Test.Org  ' }

      it 'strips whitespace and lowercases' do
        expect(parse).to eq(['example.com', 'test.org'])
      end
    end

    context 'with empty elements from consecutive commas' do
      let(:value) { ',,,' }

      it 'rejects empty elements' do
        expect(parse).to eq([])
      end
    end

    context 'with array passthrough' do
      let(:value) { ['example.com'] }

      it { is_expected.to eq(['example.com']) }
    end
  end

  describe '#parse_boolean' do
    subject(:parse) { logic.send(:parse_boolean, value) }

    context 'with nil' do
      let(:value) { nil }

      it { is_expected.to be false }
    end

    context 'with true' do
      let(:value) { true }

      it { is_expected.to be true }
    end

    context 'with false' do
      let(:value) { false }

      it { is_expected.to be false }
    end

    context 'with string "true"' do
      let(:value) { 'true' }

      it { is_expected.to be true }
    end

    context 'with string "false"' do
      let(:value) { 'false' }

      it { is_expected.to be false }
    end

    context 'with string "1"' do
      let(:value) { '1' }

      it { is_expected.to be true }
    end

    context 'with integer 1' do
      let(:value) { 1 }

      it { is_expected.to be true }
    end

    context 'with string "0"' do
      let(:value) { '0' }

      it { is_expected.to be false }
    end

    context 'with empty string' do
      let(:value) { '' }

      it { is_expected.to be false }
    end
  end

  describe '#sanitize_url' do
    subject(:sanitize) { logic.send(:sanitize_url, value) }

    context 'with nil' do
      let(:value) { nil }

      it { is_expected.to eq('') }
    end

    context 'with empty string' do
      let(:value) { '' }

      it { is_expected.to eq('') }
    end

    context 'with whitespace only' do
      let(:value) { '   ' }

      it { is_expected.to eq('') }
    end

    context 'with http URL (non-https)' do
      let(:value) { 'http://example.com' }

      it 'rejects non-https URLs' do
        expect(sanitize).to eq('')
      end
    end

    context 'with valid https URL' do
      let(:value) { 'https://auth.example.com' }

      it { is_expected.to eq('https://auth.example.com') }
    end

    context 'with https URL with surrounding whitespace' do
      let(:value) { '  https://auth.example.com  ' }

      it 'strips whitespace' do
        expect(sanitize).to eq('https://auth.example.com')
      end
    end

    context 'with invalid URL text' do
      let(:value) { 'not a url' }

      it { is_expected.to eq('') }
    end
  end
end
