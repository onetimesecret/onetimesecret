# tests/unit/ruby/rspec/config/i18n_spec.rb

# e.g. pnpm run test:rspec tests/unit/ruby/rspec/config/i18n_spec.rb

require_relative '../../spec_helper'

RSpec.describe "Internationalization config" do
  describe Onetime do
    describe '.locales' do
      context 'when config not loaded' do
        let(:original_state) do
          {
            i18n_enabled: described_class.i18n_enabled,
            locales: described_class.instance_variable_get(:@locales),
            default_locale: described_class.default_locale
          }
        end

        before do
          described_class.instance_variable_set(:@i18n_enabled, false)
          described_class.instance_variable_set(:@locales, nil)
        end

        after do
          described_class.instance_variable_set(:@i18n_enabled, original_state[:i18n_enabled])
          described_class.instance_variable_set(:@locales, original_state[:locales])
          described_class.instance_variable_set(:@default_locale, original_state[:default_locale])
        end

        it 'returns nil' do
          # Test the direct instance variable first
          expect(described_class.instance_variable_get(:@locales)).to be_nil

          # Test the accessor method behavior
          expect(described_class.locales).to be_nil
        end

        it 'does not cache empty hash after first access' do
          described_class.locales # First access
          expect(described_class.instance_variable_get(:@locales)).to be_nil
          expect(described_class.locales).to be_nil
        end
      end

      context 'when internationalization is disabled' do
        let(:original_state) do
           {
             i18n_enabled: described_class.i18n_enabled,
             locales: described_class.instance_variable_get(:@locales),
             default_locale: described_class.default_locale,
             supported_locales: described_class.supported_locales
           }
        end

         before do
           # Setup disabled internationalization state
           described_class.instance_variable_set(:@i18n_enabled, false)
           described_class.instance_variable_set(:@default_locale, 'en')
           described_class.instance_variable_set(:@supported_locales, ['en'])

           # Simulate loading only English locale
           en_locale = {greeting: 'Hello'}
           described_class.instance_variable_set(:@locales, {'en' => en_locale})
         end

         after do
           # Restore original state
           described_class.instance_variable_set(:@i18n_enabled, original_state[:i18n_enabled])
           described_class.instance_variable_set(:@locales, original_state[:locales])
           described_class.instance_variable_set(:@default_locale, original_state[:default_locale])
           described_class.instance_variable_set(:@supported_locales, original_state[:supported_locales])
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
        let(:original_state) do
          {
            i18n_enabled: described_class.i18n_enabled,
            locales: described_class.instance_variable_get(:@locales),
            default_locale: described_class.default_locale,
            supported_locales: described_class.supported_locales,
            fallback_locale: described_class.fallback_locale
          }
        end

        before do
          # Setup enabled internationalization state
          described_class.instance_variable_set(:@i18n_enabled, true)
          described_class.instance_variable_set(:@default_locale, 'fr_FR')
          described_class.instance_variable_set(:@supported_locales, %w[en fr_FR de_AT])
          described_class.instance_variable_set(:@fallback_locale, {'fr-CA': %w[fr_CA fr_FR en], default: ['en']})

          # Simulate loading multiple locales
          test_locales = {
            'en' => {greeting: 'Hello'},
            'fr_FR' => {greeting: 'Bonjour'},
            'de_AT' => {greeting: 'Grüß Gott'}
          }
          described_class.instance_variable_set(:@locales, test_locales)
        end

        after do
          # Restore original state
          described_class.instance_variable_set(:@i18n_enabled, original_state[:i18n_enabled])
          described_class.instance_variable_set(:@locales, original_state[:locales])
          described_class.instance_variable_set(:@default_locale, original_state[:default_locale])
          described_class.instance_variable_set(:@supported_locales, original_state[:supported_locales])
          described_class.instance_variable_set(:@fallback_locale, original_state[:fallback_locale])
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

  describe V2::ControllerHelpers do
    describe '#check_locale! (Regression for #1142)' do
      let(:req) { double('request', params: {}, env: {}) }
      let(:cust) { double('customer', locale: nil) }
      let(:helper) do
        Class.new do
          include V2::ControllerHelpers
          attr_accessor :req, :cust

          def initialize(req, cust)
            @req = req
            @cust = cust
          end
        end.new(req, cust)
      end

      context 'when OT.locales is nil' do
        before do
          @original_i18n_enabled = Onetime.i18n_enabled
          @original_locales = Onetime.instance_variable_get(:@locales)
          @original_default_locale = Onetime.default_locale

          # Set up the previously buggy condition
          Onetime.instance_variable_set(:@i18n_enabled, false)
          Onetime.instance_variable_set(:@locales, nil)
          Onetime.instance_variable_set(:@default_locale, 'en')

          allow(Onetime).to receive(:ld) # Suppress logs
        end

        after do
          Onetime.instance_variable_set(:@i18n_enabled, @original_i18n_enabled)
          Onetime.instance_variable_set(:@locales, @original_locales)
          Onetime.instance_variable_set(:@default_locale, @original_default_locale)
        end

        it 'handles nil locales gracefully without raising errors' do
          # This should pass after the fix is applied
          expect { helper.check_locale! }.not_to raise_error
        end

        it 'sets default locale in the environment' do
          helper.check_locale!
          expect(req.env['ots.locale']).to eq('en')
        end
      end
    end
  end
end
