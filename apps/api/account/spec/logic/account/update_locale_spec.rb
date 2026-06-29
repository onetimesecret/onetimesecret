# apps/api/account/spec/logic/account/update_locale_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'

RSpec.describe AccountAPI::Logic::Account::UpdateLocale do
  let(:supported_locales) { %w[en fr_CA fr_FR] }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:supported_locales).and_return(supported_locales)
  end

  describe 'authenticated user' do
    let(:customer) do
      instance_double(
        Onetime::Customer,
        objid: 'test-cust-123',
        role: 'customer',
        anonymous?: false,
        locale: 'en',
        'locale!': true
      )
    end

    let(:session) { {} }

    let(:strategy_result) do
      double('StrategyResult',
        session: session,
        user: customer,
        auth_method: 'sessionauth',
        metadata: {})
    end

    let(:params) { { locale: 'fr_FR' } }

    subject(:logic) { described_class.new(strategy_result, params) }

    it 'captures the old locale from the customer record' do
      expect(logic.old_locale).to eq('en')
    end

    it 'updates both the customer record and the session' do
      expect(customer).to receive(:locale!).with('fr_FR')
      logic.raise_concerns
      logic.process
      expect(session['locale']).to eq('fr_FR')
    end

    it 'returns old and new locale in success data' do
      result = logic.process
      expect(result).to include(new_locale: 'fr_FR', old_locale: 'en')
    end
  end

  # Regression coverage for #3516: anonymous (noauth) requests have a nil
  # customer, and process_params runs for every request via
  # Onetime::Logic::Base#initialize. It previously read cust.locale
  # unconditionally, raising NoMethodError (a 500) before validation.
  describe 'anonymous user (#3516)' do
    let(:session) { {} }

    let(:strategy_result) do
      double('StrategyResult',
        session: session,
        user: nil,
        auth_method: 'noauth',
        metadata: {})
    end

    let(:params) { { locale: 'fr_CA' } }

    subject(:logic) { described_class.new(strategy_result, params) }

    it 'does not raise when constructed with a nil customer' do
      expect { logic }.not_to raise_error
    end

    it 'is recognized as anonymous' do
      expect(logic.anonymous_user?).to be true
    end

    it 'reads the old locale from the session rather than a customer' do
      session['locale'] = 'en'
      expect(logic.old_locale).to eq('en')
    end

    it 'tolerates a session with no stored locale' do
      expect(logic.old_locale).to be_nil
    end

    it 'updates the session locale only' do
      logic.raise_concerns
      logic.process
      expect(session['locale']).to eq('fr_CA')
    end

    it 'marks the field modified and greenlights the update' do
      logic.process
      expect(logic.greenlighted).to be true
      expect(logic.modified?(:locale)).to be true
    end

    it 'still rejects an invalid locale' do
      invalid = described_class.new(strategy_result, { locale: 'not-a-locale' })
      expect { invalid.raise_concerns }.to raise_error(Onetime::FormError, /Invalid locale/)
    end
  end
end
