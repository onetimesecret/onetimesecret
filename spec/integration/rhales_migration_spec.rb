# frozen_string_literal: true

require 'spec_helper'
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
  end

  let(:session) { {} }
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

      it 'includes all 6 serializer outputs' do
        expect(state_data).to have_key('ui')
        expect(state_data).to have_key('authentication')
        expect(state_data).to have_key('secret_options')
        expect(state_data).to have_key('domain')
        expect(state_data).to have_key('i18n')
        expect(state_data).to have_key('messages')
        expect(state_data).to have_key('system')
      end

      it 'includes authenticated flag' do
        expect(state_data).to have_key('authenticated')
      end

      it 'includes locale' do
        expect(state_data['locale']).to eq(locale)
      end

      it 'initializes empty messages array' do
        expect(state_data['messages']).to eq([])
      end

      it 'sets window variable name to __ONETIME_STATE__' do
        expect(rendered_html).to include('window.__ONETIME_STATE__')
      end
    end

    context 'JSON Sanitization' do
      it 'escapes </script> tags in JSON content' do
        # Add a message with </script> tag
        view.add_message('Test </script> content')
        html = view.render('index')

        # JSON should not contain unescaped </script>
        expect(html).not_to include('</script> content')
        expect(html).to include('<\\/script> content').or include('&lt;/script&gt; content')
      end

      it 'handles special characters in JSON' do
        view.add_message('Test "quotes" and \'apostrophes\'')
        html = view.render('index')
        doc = Nokogiri::HTML(html)
        state_script = doc.css('script[type="application/json"]').first

        expect { JSON.parse(state_script.content) }.not_to raise_error
      end

      it 'handles newlines in JSON content' do
        view.add_message("Line 1\nLine 2")
        html = view.render('index')
        doc = Nokogiri::HTML(html)
        state_script = doc.css('script[type="application/json"]').first

        expect { JSON.parse(state_script.content) }.not_to raise_error
      end
    end

    context 'Partial Rendering' do
      it 'renders head partial' do
        expect(doc.css('meta[charset="UTF-8"]')).not_to be_empty
      end

      it 'includes all meta tags from head partial' do
        expect(doc.css('meta[name="viewport"]')).not_to be_empty
        expect(doc.css('meta[name="csrf-token"]')).not_to be_empty
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
      context 'in development mode' do
        before do
          allow_any_instance_of(Core::Views::BaseView)
            .to receive(:[]).with('frontend_development').and_return(true)
        end

        it 'includes Vite dev server script' do
          html = view.render('index')
          expect(html).to include('src="/dist/main.ts"')
          expect(html).to include('src="/dist/@vite/client"')
        end

        it 'uses type="module" for dev scripts' do
          html = view.render('index')
          doc = Nokogiri::HTML(html)
          dev_scripts = doc.css('script[src*="/dist/main.ts"]')
          expect(dev_scripts.first['type']).to eq('module')
        end
      end

      context 'in production mode' do
        before do
          allow_any_instance_of(Core::Views::BaseView)
            .to receive(:[]).with('frontend_development').and_return(false)

          # Mock manifest file
          manifest_path = File.join(
            Core::Views::ViteManifest::PUBLIC_DIR,
            'dist', '.vite', 'manifest.json'
          )
          allow(File).to receive(:exist?).with(manifest_path).and_return(true)
          allow(File).to receive(:read).with(manifest_path).and_return({
            'main.ts' => {
              'file' => 'assets/main-abc123.js',
              'css' => ['assets/main-abc123.css']
            }
          }.to_json)
        end

        it 'includes hashed asset from manifest' do
          html = view.render('index')
          expect(html).to include('assets/main-abc123.js')
        end

        it 'includes CSS from manifest' do
          html = view.render('index')
          expect(html).to include('assets/main-abc123.css')
        end
      end
    end

    context 'CSRF Token' do
      it 'includes CSRF token in meta tag' do
        csrf_meta = doc.css('meta[name="csrf-token"]').first
        expect(csrf_meta).not_to be_nil
        expect(csrf_meta['content']).not_to be_empty
      end

      it 'uses app.csrf_token from Rhales context' do
        # Verify the meta tag is populated
        csrf_meta = doc.css('meta[name="csrf-token"]').first
        expect(csrf_meta['content']).to match(/\S+/)
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
        expect(doc.css('html')).to have(1).item
        expect(doc.css('head')).to have(1).item
        expect(doc.css('body')).to have(1).item
        expect(doc.css('#app')).to have(1).item
      end

      it 'preserves all meta tags from original template' do
        # Count meta tags (should match original count)
        meta_tags = doc.css('meta')
        expect(meta_tags.length).to be >= 15  # Original has 15+ meta tags
      end
    end
  end
end
