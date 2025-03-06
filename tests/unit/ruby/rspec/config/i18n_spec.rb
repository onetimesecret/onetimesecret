# tests/unit/ruby/rspec/config/i18n_fix_spec.rb

# e.g. pnpm run rspec tests/unit/ruby/rspec/config/i18n_spec.rb

require_relative '../spec_helper'

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
          described_class.i18n_enabled = false
          described_class.instance_variable_set(:@locales, nil)
        end

        after do
          described_class.i18n_enabled = original_state[:i18n_enabled]
          described_class.instance_variable_set(:@locales, original_state[:locales])
          described_class.default_locale = original_state[:default_locale]
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

      end

    end

  end

  describe Onetime::App::WebHelpers do
    describe '#check_locale! (Regression for #1142)' do
      let(:req) { double('request', params: {}, env: {}) }
      let(:cust) { double('customer', locale: nil) }
      let(:helper) do
        Class.new do
          include Onetime::App::WebHelpers
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
          Onetime.i18n_enabled = false
          Onetime.instance_variable_set(:@locales, nil)
          Onetime.default_locale = 'en'

          allow(Onetime).to receive(:ld) # Suppress logs
        end

        after do
          Onetime.i18n_enabled = @original_i18n_enabled
          Onetime.instance_variable_set(:@locales, @original_locales)
          Onetime.default_locale = @original_default_locale
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
