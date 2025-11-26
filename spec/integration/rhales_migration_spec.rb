# spec/integration/rhales_migration_spec.rb
#
# frozen_string_literal: true

require_relative 'integration_spec_helper'
require 'nokogiri'

RSpec.describe 'Rhales Migration Integration' do
  # Initialize OT configuration for views
  before(:all) do
    # Set minimal OT locale data
    OT.instance_variable_set(:@locales, {
      'en' => {
        web: {
          COMMON: {
            title: 'Onetime Secret',
            tagline: 'Keep sensitive info out of your email & chat logs.'
          }
        }
      }
    })
    OT.instance_variable_set(:@default_locale, 'en')
    OT.instance_variable_set(:@supported_locales, ['en'])

    # Set minimal OT configuration
    mock_config = {
      'site' => {
        'host' => 'localhost:7143',
        'domain' => 'localhost',
        'ssl' => false
      },
      'development' => { 'enabled' => false },
      'diagnostics' => {},
      'billing' => { 'enabled' => false }
    }
    OT.instance_variable_set(:@conf, mock_config)

    # Configure Rhales template paths (normally done by ConfigureRhales initializer)
    unless Rhales.configuration.frozen?
      Rhales.configure do |config|
        config.nonce_header_name = 'onetime.nonce'
        config.hydration.injection_strategy = :earliest
        config.hydration_authority = :schema
        config.hydration.mount_point_selectors = ['#app']
        templates_dir = File.join(OT::HOME, 'apps', 'web', 'core', 'templates')
        config.template_paths = [templates_dir]
        config.allowed_unescaped_variables = ['vite_assets_html']
      end
    end
  end

  let(:session) { { 'csrf' => 'test-csrf-token-12345' } }
  let(:customer) { Onetime::Customer.anonymous }
  let(:locale) { 'en' }
  let(:nonce) { SecureRandom.base64(32) }

  # Mock Otto StrategyResult
  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: false,
      metadata: {}
    )
  end

  let(:request) do
    env_hash = {
      'onetime.nonce' => nonce,
      'otto.locale' => locale,
      'rack.session' => session,
      'otto.strategy_result' => strategy_result
    }

    double('Request',
      env: env_hash,
      locale: locale,
      user: customer,
      session: session,
      authenticated?: false,
      nonce: nonce,
      strategy_result: strategy_result
    ).tap do |req|
      # Allow env to respond to fetch for i18n helpers
      allow(req.env).to receive(:fetch).and_call_original
    end
  end

  describe 'VuePoint rendering with Rhales' do
    let(:view) { Core::Views::VuePoint.new(request) }
    let(:rendered_html) { view.render('index') }
    let(:doc) { Nokogiri::HTML(rendered_html) }

    context 'CSP Nonce Propagation' do
      it 'applies nonce to dark mode script' do
        dark_mode_script = doc.css('head script').first
        expect(dark_mode_script['nonce']).to eq(nonce)
      end

      it 'applies nonce to all link tags' do
        doc.css('link[nonce]').each do |link|
          expect(link['nonce']).to eq(nonce)
        end
      end

      it 'applies nonce to Vite asset scripts' do
        vite_scripts = doc.css('script[src*="/dist/"]')
        expect(vite_scripts).not_to be_empty
        vite_scripts.each do |script|
          expect(script['nonce']).to eq(nonce)
        end
      end

      it 'includes nonce in hydration script' do
        hydration_script = doc.css('script[type="application/json"]').first
        expect(hydration_script['nonce']).to eq(nonce)
      end
    end

    context 'Serializer Data Hydration' do
      let(:state_script) { doc.css('script[type="application/json"]').first }
      let(:state_data) { JSON.parse(state_script.content) }

      it 'includes serializer outputs from all registered serializers' do
        # ConfigSerializer outputs
        expect(state_data).to have_key('secret_options')
        # AuthenticationSerializer outputs
        expect(state_data).to have_key('authenticated')
        expect(state_data).to have_key('cust')
        # DomainSerializer outputs
        expect(state_data).to have_key('domain_strategy')
        # I18nSerializer outputs
        expect(state_data).to have_key('locale')
        # MessagesSerializer outputs
        expect(state_data).to have_key('messages')
        # SystemSerializer outputs
        expect(state_data).to have_key('ot_version')
        expect(state_data).to have_key('shrimp')
      end

      it 'includes authenticated flag' do
        expect(state_data).to have_key('authenticated')
      end

      it 'includes locale' do
        expect(state_data['locale']).to eq(locale)
      end

      it 'initializes messages as empty or nil' do
        # Messages start as nil in view_vars and are only populated when add_message is called
        expect(state_data['messages']).to satisfy { |m| m.nil? || m == [] }
      end

      it 'sets window variable name to __ONETIME_STATE__' do
        # Rhales uses data-window attribute to specify the window variable name
        # The hydration script reads this and sets window[name] = parsed JSON
        expect(rendered_html).to include('data-window="__ONETIME_STATE__"')
      end
    end

    context 'JSON Sanitization' do
      # Note: Messages are serialized at view initialization time.
      # These tests verify that the JSON state data is valid and properly encoded.

      it 'produces valid JSON in hydration script' do
        state_script = doc.css('script[type="application/json"]').first
        expect(state_script).not_to be_nil
        expect { JSON.parse(state_script.content) }.not_to raise_error
      end

      it 'handles special characters in serialized data' do
        # The serialized data contains various strings that may have special chars
        state_script = doc.css('script[type="application/json"]').first
        state_data = JSON.parse(state_script.content)

        # Verify JSON parsing succeeded - special characters are properly escaped
        expect(state_data).to be_a(Hash)
        expect(state_data).to have_key('ot_version')
      end

      it 'escapes angle brackets in JSON to prevent XSS' do
        state_script = doc.css('script[type="application/json"]').first
        # The raw script content should not contain unescaped </script>
        # If it did, it would prematurely close the JSON script tag
        expect(state_script.content).not_to include('</script>')
      end
    end

    context 'Partial Rendering' do
      it 'renders head partial' do
        expect(doc.css('meta[charset="UTF-8"]')).not_to be_empty
      end

      it 'includes all meta tags from head partial' do
        expect(doc.css('meta[name="viewport"]')).not_to be_empty
        expect(doc.css('meta[name="referrer"]')).not_to be_empty
        expect(doc.css('meta[property="og:url"]')).not_to be_empty
        expect(doc.css('meta[name="twitter:card"]')).not_to be_empty
      end

      it 'renders page title from props' do
        expect(doc.css('title').text).not_to be_empty
      end

      it 'includes favicon links' do
        expect(doc.css('link[rel="icon"]')).not_to be_empty
      end
    end

    context 'Vite Asset Loading' do
      # Note: These tests verify that vite_assets_html is included in the template.
      # The actual asset paths depend on whether a manifest exists and development mode.
      # More detailed Vite behavior is tested in unit tests.

      it 'includes script tags for Vite assets' do
        # The template should include script tags for the main entry point
        # In test mode without manifest, it may use fallback or dev mode paths
        vite_scripts = doc.css('script[type="module"]')
        expect(vite_scripts).not_to be_empty
      end

      it 'applies nonces to Vite script tags' do
        module_scripts = doc.css('script[type="module"][nonce]')
        module_scripts.each do |script|
          expect(script['nonce']).to eq(nonce)
        end
      end
    end

    context 'CSRF Token' do
      it 'delivers CSRF via shrimp in serialized state (not meta tag)' do
        # CSRF is delivered via window.__ONETIME_STATE__.shrimp and X-CSRF-Token header
        # No meta tag - frontend reads from window state, updates from response headers
        state_script = doc.css('script[type="application/json"]').first
        state_data = JSON.parse(state_script.content)
        expect(state_data).to have_key('shrimp')
      end
    end

    context 'Dark Mode Script' do
      it 'includes dark mode initialization script' do
        expect(rendered_html).to include('prefers-color-scheme: dark')
        expect(rendered_html).to include('adjustVisualEnvironment')
      end

      it 'positions dark mode script as first child of head' do
        first_script = doc.css('head script').first
        expect(first_script.content).to include('prefers-color-scheme: dark')
      end

      it 'applies nonce to dark mode script' do
        first_script = doc.css('head script').first
        expect(first_script['nonce']).to eq(nonce)
      end

      it 'sets up dark/light mode classes' do
        expect(rendered_html).to include('addClass: \'dark\'')
        expect(rendered_html).to include('addClass: \'light\'')
      end
    end

    context 'Vue.js SPA Structure' do
      it 'includes #app mount point' do
        app_div = doc.css('#app').first
        expect(app_div).not_to be_nil
      end

      it 'includes router-view inside #app' do
        router_view = doc.css('#app router-view').first
        expect(router_view).not_to be_nil
      end

      it 'sets html lang attribute from locale' do
        expect(doc.css('html').first['lang']).to eq(locale)
      end

      it 'applies initial light mode class to html' do
        expect(doc.css('html').first['class']).to include('light')
      end
    end

    context 'Backward Compatibility' do
      it 'maintains same HTML structure' do
        # Verify essential structure elements
        expect(doc.css('html').length).to eq(1)
        expect(doc.css('head').length).to eq(1)
        expect(doc.css('body').length).to eq(1)
        expect(doc.css('#app').length).to eq(1)
      end

      it 'preserves all meta tags from original template' do
        # Count meta tags (should match original count)
        meta_tags = doc.css('meta')
        expect(meta_tags.length).to be >= 15  # Original has 15+ meta tags
      end
    end
  end
end
