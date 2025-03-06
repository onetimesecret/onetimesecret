# tests/unit/ruby/rspec/config/i18n_fix_spec.rb

require_relative '../spec_helper'

RSpec.describe Onetime do
  describe '.load_locales' do
    before(:each) do
      # Save current state
      @original_i18n_enabled = described_class.i18n_enabled
      @original_locales = described_class.instance_variable_get(:@locales)
      @original_default_locale = described_class.default_locale
      @original_supported_locales = described_class.supported_locales
    end

    after(:each) do
      # Restore state
      described_class.i18n_enabled = @original_i18n_enabled
      described_class.instance_variable_set(:@locales, @original_locales)
      described_class.default_locale = @original_default_locale
      described_class.supported_locales = @original_supported_locales
    end

    context 'when internationalization is disabled' do
      before do
        # Create a test configuration with internationalization disabled
        conf = {
          internationalization: {
            enabled: false,
            default_locale: 'en',
            locales: ['en', 'fr']
          }
        }
        allow(described_class).to receive(:conf).and_return(conf)

        # Reset locales to nil to simulate fresh load
        described_class.instance_variable_set(:@locales, nil)

        # Run the method
        described_class.send(:load_locales)
      end

      it 'initializes @locales as a hash' do
        expect(described_class.locales).to be_a(Hash)
      end

      it 'allows checking if locale exists without error' do
        expect { described_class.locales.has_key?('en') }.not_to raise_error
      end
    end

    context 'when internationalization is enabled' do
      before do
        # Create a test configuration with internationalization enabled
        conf = {
          internationalization: {
            enabled: true,
            default_locale: 'en',
            locales: ['en', 'fr']
          }
        }
        allow(described_class).to receive(:conf).and_return(conf)

        # Mock file loading since we don't want to rely on actual files
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return('{"test":"value"}')
        allow(JSON).to receive(:parse).and_return({test: "value"})

        # Reset locales to nil to simulate fresh load
        described_class.instance_variable_set(:@locales, nil)

        # Run the method
        described_class.send(:load_locales)
      end

      it 'initializes @locales as a hash' do
        expect(described_class.locales).to be_a(Hash)
      end
    end
  end

  describe '#check_locale!' do
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

        # Create a problematic state to test fix
        Onetime.i18n_enabled = false
        Onetime.instance_variable_set(:@locales, nil) # Simulate buggy state
        Onetime.default_locale = 'en'

        allow(Onetime).to receive(:ld) # Suppress logging output
      end

      after do
        Onetime.i18n_enabled = @original_i18n_enabled
        Onetime.instance_variable_set(:@locales, @original_locales)
        Onetime.default_locale = @original_default_locale
      end

      it 'should not raise error when checking locale' do
        expect { helper.check_locale! }.not_to raise_error
      end
    end
  end
end
