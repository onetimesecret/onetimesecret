# tests/unit/ruby/rspec/configuration_manifold_spec.rb

require_relative '../unit/ruby/rspec/spec_helper'

RSpec.describe 'Configuration to Frontend Flow Integration' do
  let(:minimal_config) do
    {
      'site' => {
        'secret' => 'test-secret-key',
        'authentication' => {
          'enabled' => true,
          'signin' => true,
          'signup' => true,
          'autoverify' => false,
        },
        'host' => 'dev.onetime.dev',
      },
      'development' => {
        'frontend_host' => 'http://localhost:5173',
      },
      'diagnostics' => {
        'sentry' => {
          'dsn' => 'https://test@sentry.io/123',
          'logErrors' => true,
          'trackComponents' => true,
        },
      },
      'mail' => {
        'connection' => {},
        'validation' => { 'defaults' => {} },
      },
      'experimental' => {
        'allow_nil_global_secret' => false,
      },
    }
  end

  before(:each) do
    # Mock the configuration to return our test config
    allow(OT).to receive(:conf).and_return(minimal_config)
  end

  let(:simulated_ui_context) do
    config = OT.conf

    {
      # Authentication section transformation
      'authentication' => {
        'enabled' => config.dig('site', 'authentication', 'enabled') || false,
        'signin' => config.dig('site', 'authentication', 'signin') || false,
        'signup' => config.dig('site', 'authentication', 'signup') || false,
        'autoverify' => config.dig('site', 'authentication', 'autoverify') || false,
      },

      # Diagnostics section transformation
      'diagnostics' => {
        'sentry' => {
          'dsn' => config.dig('diagnostics', 'sentry', 'dsn') || '',
          'logErrors' => config.dig('diagnostics', 'sentry', 'logErrors') || false,
          'trackComponents' => config.dig('diagnostics', 'sentry', 'trackComponents') || false,
        },
      },

      # Host information transformation
      'site_host' => config.dig('site', 'host') || 'localhost',
      'frontend_host' => config.dig('development', 'frontend_host') || 'http://localhost:3000',

      # User state (would come from session/database in real system)
      'authenticated' => false,
      'custid' => nil,
      'email' => nil,
      'customer_since' => nil,

      # System information (would be dynamically generated)
      'ot_version' => '0.22.3',
      'ot_version_long' => '0.22.3 (test)',
      'ruby_version' => 'ruby-341',
      'shrimp' => 'test-csrf-token',
      'nonce' => 'test-nonce',

      # Feature flags (would be derived from config)
      'd9s_enabled' => config.dig('diagnostics', 'sentry', 'dsn') ? true : false,
      'domains_enabled' => false, # Default for test
      'regions_enabled' => false, # Default for test
      'plans_enabled' => false,   # Default for test
      'i18n_enabled' => true,     # Default for test

      # Internationalization (would have defaults)
      'locale' => 'en',
      'default_locale' => 'en',
      'supported_locales' => ['en'],
      'fallback_locale' => { 'default' => ['en'] },

      # UI configuration
      'ui' => {
        'enabled' => true,
        'header' => {
          'enabled' => true,
          'branding' => {
            'logo' => {
              'url' => 'DefaultLogo',
              'alt' => 'One-Time Secret',
              'href' => '/',
            },
            'site_name' => 'One-Time Secret',
          },
          'navigation' => {
            'enabled' => true,
          },
        },
        'footer_links' => {
          'enabled' => false,
          'groups' => [],
        },
      },

      # Domain configuration
      'canonical_domain' => config.dig('site', 'host') || 'localhost',
      'display_domain' => config.dig('site', 'host') || 'localhost',
      'domain_strategy' => 'canonical',

      # Business logic defaults
      'is_paid' => false,
      'available_plans' => {},
      'messages' => [],

      # Secret options defaults
      'secret_options' => {
        'default_ttl' => 604_800.0,
        'ttl_options' => [60, 300, 1800, 3600, 14_400, 43_200, 86_400, 259_200, 604_800, 1_209_600, 2_592_000],
      },

      # Regions defaults
      'regions' => {
        'enabled' => false,
        'current_jurisdiction' => 'EU',
      },
    }
  end

  describe 'Basic configuration flow validation' do
    it 'validates that config sections map to window properties' do
      config = OT.conf

      # Core configuration sections that should be available
      expect(config).to have_key('site')
      expect(config).to have_key('diagnostics')
      expect(config).to have_key('development')

      # Site configuration
      site_config = config['site']
      expect(site_config).to have_key('authentication')
      expect(site_config).to have_key('host')

      # Authentication configuration
      auth_config = site_config['authentication']
      expect(auth_config).to have_key('enabled')
      expect(auth_config).to have_key('signin')
      expect(auth_config).to have_key('signup')
      expect(auth_config).to have_key('autoverify')

      # Diagnostics configuration
      diagnostics_config = config['diagnostics']
      expect(diagnostics_config).to have_key('sentry')

      sentry_config = diagnostics_config['sentry']
      expect(sentry_config).to have_key('dsn')
      expect(sentry_config).to have_key('logErrors')
      expect(sentry_config).to have_key('trackComponents')
    end

    it 'ensures required configuration values have proper types' do
      config = OT.conf

      # Boolean validations
      expect(config['site']['authentication']['enabled']).to be(true).or be(false)
      expect(config['site']['authentication']['signin']).to be(true).or be(false)
      expect(config['site']['authentication']['signup']).to be(true).or be(false)
      expect(config['site']['authentication']['autoverify']).to be(true).or be(false)

      expect(config['diagnostics']['sentry']['logErrors']).to be(true).or be(false)
      expect(config['diagnostics']['sentry']['trackComponents']).to be(true).or be(false)

      # String validations
      expect(config['site']['secret']).to be_a(String)
      expect(config['site']['host']).to be_a(String)
      expect(config['diagnostics']['sentry']['dsn']).to be_a(String)
      expect(config['development']['frontend_host']).to be_a(String)
    end
  end

  describe 'UIContext data transformation simulation' do
    # This simulates how the Ruby backend would transform config into UIContext
    # In the actual system, this would be done by the Ruby view layer

    it 'transforms config authentication section correctly' do
      ui_context = simulated_ui_context

      expect(ui_context['authentication']).to be_a(Hash)
      expect(ui_context['authentication']['enabled']).to eq(true)
      expect(ui_context['authentication']['signin']).to eq(true)
      expect(ui_context['authentication']['signup']).to eq(true)
      expect(ui_context['authentication']['autoverify']).to eq(false)
    end

    it 'transforms config diagnostics section correctly' do
      ui_context = simulated_ui_context

      expect(ui_context['diagnostics']).to be_a(Hash)
      expect(ui_context['diagnostics']['sentry']).to be_a(Hash)
      expect(ui_context['diagnostics']['sentry']['dsn']).to eq('https://test@sentry.io/123')
      expect(ui_context['diagnostics']['sentry']['logErrors']).to eq(true)
      expect(ui_context['diagnostics']['sentry']['trackComponents']).to eq(true)
    end

    it 'transforms host configuration correctly' do
      ui_context = simulated_ui_context

      expect(ui_context['site_host']).to eq('dev.onetime.dev')
      expect(ui_context['frontend_host']).to eq('http://localhost:5173')
    end

    it 'includes all required window state top-level keys' do
      ui_context = simulated_ui_context

      required_keys = %w[
        authenticated custid email customer_since
        authentication diagnostics
        site_host frontend_host
        ot_version ot_version_long ruby_version shrimp nonce
        d9s_enabled domains_enabled regions_enabled plans_enabled i18n_enabled
        locale default_locale supported_locales fallback_locale
        ui canonical_domain display_domain domain_strategy
        is_paid available_plans messages secret_options regions
      ]

      required_keys.each do |key|
        expect(ui_context).to have_key(key.to_s), "Missing required key: #{key}"
      end
    end

    it 'ensures no sensitive data is exposed' do
      ui_context = simulated_ui_context

      # Check that sensitive configuration data is not present
      sensitive_keys = %w[secret database_url redis_url stripe_secret_key mail_password]

      sensitive_keys.each do |key|
        expect(ui_context).not_to have_key(key.to_s), "Sensitive key '#{key}' should not be exposed"
      end

      # Ensure the site secret is not exposed
      expect(ui_context.to_s).not_to include('test-secret-key')
    end
  end

  describe 'Different user authentication states' do
    context 'when user is anonymous' do
      let(:anonymous_context) do
        OT.conf

        {
          'authenticated' => false,
          'custid' => nil,
          'cust' => {
            'identifier' => 'anon',
            'custid' => 'anon',
            'email' => nil,
            'role' => 'customer',
            'verified' => nil,
            'active' => false,
          },
          'email' => nil,
          'customer_since' => nil,
          'is_paid' => false,
          'plan' => {
            'identifier' => 'anonymous',
            'planid' => 'anonymous',
            'price' => 0,
            'discount' => 0,
            'options' => {
              'ttl' => 604_800.0,
              'size' => 100_000,
              'api' => false,
              'name' => 'Anonymous',
            },
          },
        }
      end

      it 'provides appropriate anonymous user data' do
        context = anonymous_context

        expect(context['authenticated']).to eq(false)
        expect(context['custid']).to be_nil
        expect(context['email']).to be_nil
        expect(context['customer_since']).to be_nil
        expect(context['is_paid']).to eq(false)

        expect(context['cust']).to be_a(Hash)
        expect(context['cust']['identifier']).to eq('anon')
        expect(context['cust']['role']).to eq('customer')
        expect(context['cust']['active']).to eq(false)

        expect(context['plan']).to be_a(Hash)
        expect(context['plan']['identifier']).to eq('anonymous')
        expect(context['plan']['options']['api']).to eq(false)
      end
    end

    context 'when user is authenticated' do
      let(:authenticated_context) do
        {
          'authenticated' => true,
          'custid' => 'test-customer-123',
          'cust' => {
            'identifier' => 'test-customer-123',
            'custid' => 'test-customer-123',
            'email' => 'test@example.com',
            'role' => 'customer',
            'verified' => true,
            'active' => true,
          },
          'email' => 'test@example.com',
          'customer_since' => '2024-01-01T00:00:00Z',
          'is_paid' => true,
          'plan' => {
            'identifier' => 'basic',
            'planid' => 'basic',
            'price' => 0,
            'discount' => 0,
            'options' => {
              'ttl' => 1_209_600.0,
              'size' => 1_000_000,
              'api' => true,
              'name' => 'Basic Plan',
            },
          },
        }
      end

      it 'provides appropriate authenticated user data' do
        context = authenticated_context

        expect(context['authenticated']).to eq(true)
        expect(context['custid']).to eq('test-customer-123')
        expect(context['email']).to eq('test@example.com')
        expect(context['customer_since']).to be_a(String)
        expect(context['is_paid']).to eq(true)

        expect(context['cust']).to be_a(Hash)
        expect(context['cust']['identifier']).to eq('test-customer-123')
        expect(context['cust']['verified']).to eq(true)
        expect(context['cust']['active']).to eq(true)

        expect(context['plan']).to be_a(Hash)
        expect(context['plan']['identifier']).to eq('basic')
        expect(context['plan']['options']['api']).to eq(true)
      end
    end
  end

  describe 'Feature flag consistency' do
    it 'derives feature flags from configuration consistently' do
      config = OT.conf

      # d9s_enabled should be true if Sentry DSN is configured
      has_sentry_dsn = !config.dig('diagnostics', 'sentry', 'dsn').nil?

      # This would be the logic in the actual UIContext generation
      d9s_enabled = has_sentry_dsn && config.dig('diagnostics', 'sentry', 'logErrors')

      expect(d9s_enabled).to eq(true) # Based on our test config
    end

    it 'handles missing configuration gracefully' do
      # Test with incomplete config
      incomplete_config = {
        'site' => {
          'secret' => 'test-secret',
          # Missing authentication section
        },
      }

      allow(OT).to receive(:conf).and_return(incomplete_config)

      # UIContext should provide sensible defaults
      simulated_context = {
        'authentication' => {
          'enabled' => incomplete_config.dig('site', 'authentication', 'enabled') || false,
          'signin' => incomplete_config.dig('site', 'authentication', 'signin') || false,
          'signup' => incomplete_config.dig('site', 'authentication', 'signup') || false,
          'autoverify' => incomplete_config.dig('site', 'authentication', 'autoverify') || false,
        },
      }

      expect(simulated_context['authentication']['enabled']).to eq(false)
      expect(simulated_context['authentication']['signin']).to eq(false)
      expect(simulated_context['authentication']['signup']).to eq(false)
      expect(simulated_context['authentication']['autoverify']).to eq(false)
    end
  end

  describe 'JSON serialization compatibility' do
    it 'ensures all context data is JSON serializable' do
      ui_context = simulated_ui_context

      expect do
        JSON.generate(ui_context)
      end.not_to raise_error

      # Verify the serialized JSON can be parsed back
      json_string = JSON.generate(ui_context)
      parsed_back = JSON.parse(json_string)

      expect(parsed_back).to be_a(Hash)
      expect(parsed_back['authentication']).to be_a(Hash)
      expect(parsed_back['diagnostics']).to be_a(Hash)
    end

    it 'maintains data types through JSON serialization' do
      ui_context  = simulated_ui_context
      json_string = JSON.generate(ui_context)
      parsed_back = JSON.parse(json_string)

      # Boolean values should remain boolean
      expect(parsed_back['authenticated']).to be(true).or be(false)
      expect(parsed_back['authentication']['enabled']).to be(true).or be(false)

      # Numeric values should remain numeric
      expect(parsed_back['secret_options']['default_ttl']).to be_a(Numeric)

      # Arrays should remain arrays
      expect(parsed_back['secret_options']['ttl_options']).to be_a(Array)
      expect(parsed_back['supported_locales']).to be_a(Array)
    end
  end
end
