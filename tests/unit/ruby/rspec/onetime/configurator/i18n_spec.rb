# tests/unit/ruby/rspec/onetime/configurator/i18n_spec.rb

require_relative '../../spec_helper'

RSpec.describe "Internationalization config" do
  describe "Onetime legacy global methods" do
    # Note: These tests are currently pending because the LegacyGlobals module
    # is not loaded in the test environment. The module is loaded via the
    # system services in production but not in unit tests.

    it 'has legacy global methods available in production' do
      pending 'LegacyGlobals module not loaded in test environment'

      # These methods should be available when the system is fully loaded:
      # - Onetime.i18n_enabled
      # - Onetime.locales
      # - Onetime.default_locale
      # - Onetime.fallback_locale
      # - Onetime.supported_locales
      # - Onetime.global_banner
      # - Onetime.emailer
      # - Onetime.global_secret
      # - Onetime.d9s_enabled

      expect(Onetime).to respond_to(:i18n_enabled)
    end
  end

  describe 'V2::ControllerHelpers' do
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
          # Mock the OT.conf to return nil to simulate no config loaded
          allow(OT).to receive(:conf).and_return(nil)
          allow(OT).to receive(:lw) # Suppress warnings
        end

        it 'handles nil locales gracefully without raising errors' do
          # pending 'Bug: check_locale! method does not handle nil OT.conf gracefully'
          # This test verifies that check_locale! doesn't crash when
          # the locales configuration is not available
          expect { helper.check_locale! }.not_to raise_error
        end

        it 'sets a default locale in the environment' do
          # pending 'Bug: check_locale! method does not handle nil OT.conf gracefully'
          helper.check_locale!
          # Should set some default locale even when config is nil
          expect(req.env['ots.locale']).not_to be_nil
        end
      end

      context 'when locales configuration is available' do
        # NOTE: With this mock config, the pre-configproxy code would rightly
        # expect that this config was available via OT.conf. It's a reasonable
        # assumption b/c OT.conf would get to the config hash immediately
        # on startup (since it was simply reading in the YAML file). IOW,
        # `helper.check_locale!` code to check OT.ready? isn't relevant here.
        # And I think it means that we can't (or shouldn't?) have the behaviour
        # where OT.conf is nil until OT.ready? OT.conf should still provide
        # the core static config as soon as it can (as long as it is validated
        # and the defaults are applied).
        let(:mock_config) do
          {
            'i18n' => { 'enabled' => true, 'default_locale' => 'en' },
            'locales' => { 'en' => {}, 'fr' => {} },
            'supported_locales' => %w[en fr]
          }
        end

        before do
          allow(OT).to receive(:conf).and_return(mock_config)
          allow(OT).to receive(:lw) # Suppress warnings
        end

        it 'uses the configured default locale' do
          # pending 'Bug: check_locale! method access pattern needs fixing for symbol/string keys'
          helper.check_locale!
          expect(req.env['ots.locale']).to eq('en')
        end

        it 'handles locale parameter from request' do
          # pending 'Bug: check_locale! method access pattern needs fixing for symbol/string keys'
          allow(req).to receive(:params).and_return({ 'locale' => 'fr' })
          helper.check_locale!
          expect(req.env['ots.locale']).to eq('fr')
        end
      end
    end
  end
end
