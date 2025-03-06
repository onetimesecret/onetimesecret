# tests/unit/ruby/rspec/config/i18n_spec.rb

require_relative '../spec_helper'

RSpec.describe Onetime do
  describe '.locales' do
    context 'when internationalization is disabled' do
      before do
        # Save original state to restore after test
        @original_i18n_enabled = described_class.i18n_enabled
        @original_locales = described_class.instance_variable_get(:@locales)

        # Simulate disabled internationalization
        described_class.i18n_enabled = false
        described_class.remove_instance_variable(:@locales) if described_class.instance_variable_defined?(:@locales)
      end

      after do
        # Restore original state
        described_class.i18n_enabled = @original_i18n_enabled
        described_class.instance_variable_set(:@locales, @original_locales)
      end

      it 'should return a hash even when internationalization is disabled' do
        # This test fails currently because OT.locales returns nil
        expect(described_class.locales).to be_a(Hash)
      end

      it 'should not raise error when checking if locale exists' do
        expect { described_class.locales.has_key?('en') }.not_to raise_error
      end
    end

    context 'when internationalization is enabled' do
      before do
        # Save original state to restore after test
        @original_i18n_enabled = described_class.i18n_enabled
        @original_locales = described_class.instance_variable_get(:@locales)
        @original_default_locale = described_class.default_locale

        # Simulate enabled internationalization
        described_class.i18n_enabled = true
        described_class.instance_variable_set(:@locales, {'en' => {}})
        described_class.default_locale = 'en'
      end

      after do
        # Restore original state
        described_class.i18n_enabled = @original_i18n_enabled
        described_class.instance_variable_set(:@locales, @original_locales)
        described_class.default_locale = @original_default_locale
      end

      it 'should return the configured locales' do
        expect(described_class.locales).to eq({'en' => {}})
      end

      it 'should check if locale exists without error' do
        expect(described_class.locales.has_key?('en')).to be true
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

        Onetime.i18n_enabled = false
        Onetime.remove_instance_variable(:@locales) if Onetime.instance_variable_defined?(:@locales)
        Onetime.default_locale = 'en'
      end

      after do
        Onetime.i18n_enabled = @original_i18n_enabled
        Onetime.instance_variable_set(:@locales, @original_locales)
        Onetime.default_locale = @original_default_locale
      end

      it 'should not raise error when checking locale' do
        expect { helper.check_locale! }.not_to raise_error
      end

      it 'should set default locale when locales is nil' do
        helper.check_locale!
        expect(req.env['ots.locale']).to eq('en')
      end
    end
  end
end
