# tests/unit/ruby/rspec/onetime/configurator/i18n_spec.rb

require_relative '../../../spec_helper'
require 'onetime/services/legacy_globals'
require 'onetime/services/service_registry'

RSpec.describe "Internationalization config" do
  describe "Onetime legacy global methods" do
    # Note: These tests are currently pending because the LegacyGlobals module
    # is not loaded in the test environment. The module is loaded via the
    # system services in production but not in unit tests.

    it 'has legacy global methods available when LegacyGlobals is loaded' do
      # Mock OT.conf (not Onetime.state) since LegacyGlobals uses OT.conf
      mock_config = {
        'i18n' => { 'enabled' => true, 'default_locale' => 'en', 'fallback_locale' => nil },
        'locales' => { 'en' => {}, 'fr' => {} },
        'supported_locales' => ['en', 'fr'],
        'global_banner' => nil,
        'diagnostics' => { 'enabled' => false },
        'site' => { 'secret' => 'test_secret' }
      }

      allow(OT).to receive(:conf).and_return(mock_config)
      allow(Onetime::Services::ServiceRegistry).to receive(:get_state).with(:mailer_class).and_return('MockMailer')
      allow(Onetime::Services::LegacyGlobals).to receive(:print_warning) # Suppress warning output

      # These methods should be available when LegacyGlobals is loaded:
      expect(Onetime).to respond_to(:i18n_enabled)
      expect(Onetime).to respond_to(:locales)
      expect(Onetime).to respond_to(:default_locale)
      expect(Onetime).to respond_to(:fallback_locale)
      expect(Onetime).to respond_to(:supported_locales)
      expect(Onetime).to respond_to(:global_banner)
      expect(Onetime).to respond_to(:emailer)
      expect(Onetime).to respond_to(:global_secret)
      expect(Onetime).to respond_to(:d9s_enabled)

      # Test that the methods return expected values
      expect(Onetime.i18n_enabled).to be(true)
      expect(Onetime.locales).to eq({ 'en' => {}, 'fr' => {} })
      expect(Onetime.default_locale).to eq('en')
      expect(Onetime.supported_locales).to eq(['en', 'fr'])
      expect(Onetime.fallback_locale).to be_nil
      expect(Onetime.global_banner).to be_nil
      expect(Onetime.d9s_enabled).to be(false)
      expect(Onetime.global_secret).to eq('test_secret')
      expect(Onetime.emailer).to eq('MockMailer')
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
          # This test verifies that check_locale! doesn't crash when
          # the locales configuration is not available
          expect { helper.check_locale! }.not_to raise_error

          # Verify the method completed and set a locale
          expect(req.env).to have_key('ots.locale')
          expect(helper.instance_variable_get(:@locale)).not_to be_nil
        end

        it 'sets a default locale in the environment' do
          helper.check_locale!

          # Should set some default locale even when config is nil
          expect(req.env['ots.locale']).not_to be_nil
          expect(req.env['ots.locale']).to eq('en') # Should default to 'en'
          expect(helper.instance_variable_get(:@locale)).to eq('en')
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
          helper.check_locale!

          expect(req.env['ots.locale']).to eq('en')
          expect(helper.instance_variable_get(:@locale)).to eq('en')
        end

        it 'handles locale parameter from request' do
          # Fix: Use symbol key since check_locale! accesses req.params[:locale]
          allow(req).to receive(:params).and_return({ locale: 'fr' })

          helper.check_locale!

          expect(req.env['ots.locale']).to eq('fr')
          expect(helper.instance_variable_get(:@locale)).to eq('fr')
        end

        it 'falls back to default when unsupported locale is requested' do
          allow(req).to receive(:params).and_return({ locale: 'unsupported' })

          helper.check_locale!

          expect(req.env['ots.locale']).to eq('en') # Should fall back to default
          expect(helper.instance_variable_get(:@locale)).to eq('en')
        end

        it 'prioritizes request parameter over customer locale' do
          allow(req).to receive(:params).and_return({ locale: 'fr' })
          allow(cust).to receive(:locale).and_return('en')

          helper.check_locale!

          expect(req.env['ots.locale']).to eq('fr') # Request parameter wins
          expect(helper.instance_variable_get(:@locale)).to eq('fr')
        end

        it 'uses customer locale when no request parameter is provided' do
          allow(req).to receive(:params).and_return({})
          allow(cust).to receive(:locale).and_return('fr')

          helper.check_locale!

          expect(req.env['ots.locale']).to eq('fr') # Customer locale used
          expect(helper.instance_variable_get(:@locale)).to eq('fr')
        end
      end
    end
  end
end
