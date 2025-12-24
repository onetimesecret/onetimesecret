# spec/onetime/config/i18n_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Internationalization config" do
  describe Onetime do
    describe '.locales' do
      context 'when config not loaded' do
        let(:original_i18n) { Onetime::Runtime.internationalization }

        before do
          # Set up a disabled i18n state with nil locales to simulate unloaded config
          Onetime::Runtime.internationalization = Onetime::Runtime::Internationalization.new(
            enabled: false,
            supported_locales: [],
            default_locale: 'en',
            fallback_locale: 'en',
            locales: nil
          )
        end

        after do
          Onetime::Runtime.internationalization = original_i18n
        end

        it 'returns nil' do
          expect(described_class.locales).to be_nil
        end

        it 'does not cache empty hash after first access' do
          described_class.locales # First access
          expect(described_class.locales).to be_nil
        end
      end

      context 'when internationalization is disabled' do
        let(:original_i18n) { Onetime::Runtime.internationalization }

        before do
          # Setup disabled internationalization state with only English locale
          Onetime::Runtime.internationalization = Onetime::Runtime::Internationalization.new(
            enabled: false,
            supported_locales: ['en'],
            default_locale: 'en',
            fallback_locale: 'en',
            locales: {'en' => {greeting: 'Hello'}}
          )
        end

        after do
          Onetime::Runtime.internationalization = original_i18n
        end

        it 'returns only English locale' do
          expect(described_class.locales).to include('en')
          expect(described_class.locales.keys.length).to eq(1)
        end

        it 'has English as default locale' do
          expect(described_class.default_locale).to eq('en')
        end

        it 'only has English in supported locales' do
          expect(described_class.supported_locales).to eq(['en'])
        end

        it 'accesses locale content correctly' do
          expect(described_class.locales['en'][:greeting]).to eq('Hello')
        end
      end

      context 'when internationalization is enabled' do
        let(:original_i18n) { Onetime::Runtime.internationalization }

        before do
          # Setup enabled internationalization state with multiple locales
          Onetime::Runtime.internationalization = Onetime::Runtime::Internationalization.new(
            enabled: true,
            supported_locales: %w[en fr_FR de_AT],
            default_locale: 'fr_FR',
            fallback_locale: {'fr-CA': %w[fr_CA fr_FR en], default: ['en']},
            locales: {
              'en' => {greeting: 'Hello'},
              'fr_FR' => {greeting: 'Bonjour'},
              'de_AT' => {greeting: 'Grüß Gott'},
            }
          )
        end

        after do
          Onetime::Runtime.internationalization = original_i18n
        end

        it 'returns all configured locales' do
          expect(described_class.locales.keys).to contain_exactly('en', 'fr_FR', 'de_AT')
        end

        it 'uses French as default locale' do
          expect(described_class.default_locale).to eq('fr_FR')
        end

        it 'includes all locales in supported locales' do
          expect(described_class.supported_locales).to eq(%w[en fr_FR de_AT])
        end

        it 'accesses specific locale content correctly' do
          expect(described_class.locales['fr_FR'][:greeting]).to eq('Bonjour')
          expect(described_class.locales['de_AT'][:greeting]).to eq('Grüß Gott')
        end

        it 'respects configured fallback locales' do
          expect(described_class.fallback_locale[:'fr-CA']).to eq(%w[fr_CA fr_FR en])
          expect(described_class.fallback_locale[:default]).to eq(['en'])
        end
      end
    end
  end

  # NOTE: V2::ControllerHelpers tests removed - V2 API deprecated, module no longer exists.
  # Regression test for #1142 was for old V2 API. V1::ControllerHelpers handles locale
  # checking in the current implementation (apps/api/v1/controllers/helpers.rb).
end
