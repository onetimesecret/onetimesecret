# spec/apps/web/views/base_spec.rb

# e.g. pnpm run rspec tests/unit/ruby/rspec/apps/web/views/base_spec.rb

require_relative '../../../spec_helper'

require 'core/views/base'
require 'core/views/serializers'

RSpec.describe Core::Views::BaseView do
  include_context "rack_test_context"
  include_context "view_test_context"

  before(:all) do
    described_class.use_serializers(
      Core::Views::ConfigSerializer,
      Core::Views::AuthenticationSerializer,
      Core::Views::DomainSerializer,
      Core::Views::I18nSerializer,
      Core::Views::MessagesSerializer,
      Core::Views::SystemSerializer,
    )
  end

  before(:each) do
    allow(OT).to receive('default_locale').and_return('en')
    allow(OT).to receive('fallback_locale').and_return('en')
    allow(OT).to receive('supported_locales').and_return(['en'])
    allow(OT).to receive('i18n_enabled').and_return(true)

    allow(OT).to receive('locales').and_return({
      'en' => {
        web: {
          COMMON: {
            description: 'Test Description',
            keywords: 'test,keywords',
          },
        },
      },
    })
  end

  subject { described_class.new(rack_request, session, customer) }

  describe '#initialize' do
    it 'sets basic template variables' do
      expect(subject['description']).to eq('Test Description')
      expect(subject['keywords']).to eq('test,keywords')
      expect(subject['page_title']).to eq('Onetime Secret')
    end

    it 'initializes JavaScript variables' do
      vars = subject.serialized_data
      expect(vars['authenticated']).to be true
      expect(vars['custid']).to eq('test@example.com')
      expect(vars['email']).to eq('test@example.com')
      expect(vars['shrimp']).to eq('test_shrimp')
    end

    it 'includes authentication configuration' do
      expect(subject.serialized_data['authentication']).to eq({
        'enabled' => true,
        'signup' => true,
      })
    end

    it 'includes secret options' do
      expect(subject.serialized_data['secret_options']).to eq({
        'default_ttl' => 86_400,
        'ttl_options' => [3600, 86_400],
      })
    end

    context 'with development mode' do
      let(:config) do
        super().merge(
          'development' => {
            'enabled' => true,
            'frontend_host' => 'http://localhost:5173',
          },
        )
      end

      it 'sets development-specific variables' do
        expect(subject['frontend_host']).to eq('http://localhost:5173')
        expect(subject['frontend_development']).to be true
      end
    end

    context 'with anonymous user' do
      let(:customer) do
        instance_double(V2::Customer,
          anonymous?: true,
          planid: 'anonymous',
          custid: nil,
          safe_dump: {
            "identifier" => "anon",
            "custid" => "anon",
            "role" => "customer",
            "verified" => nil,
            "last_login" => nil,
            "locale" => "",
            "updated" => nil,
            "created" => nil,
            "stripe_customer_id" => nil,
            "stripe_subscription_id" => nil,
            "stripe_checkout_email" => nil,
            "secrets_created" => "0",
            "secrets_burned" => "0",
            "secrets_shared" => "0",
            "emails_sent" => "0",
            "active" => false,
          })
      end

      it 'sets appropriate anonymous state' do
        vars = subject.serialized_data
        expect(vars['authenticated']).to be false
        expect(vars['custid']).to be_nil
        expect(vars['email']).to be_nil
      end
    end
  end

  describe '#add_message' do
    it 'adds info message to messages array' do
      subject.add_message('Test message')
      expect(subject.messages).to include({
        'type' => 'info',
        'content' => 'Test message',
      })
    end

    it 'adds error message to messages array' do
      subject.add_error('Error message')
      expect(subject.messages).to include({
        'type' => 'error',
        'content' => 'Error message',
      })
    end
  end

  context 'with diagnostics configuration' do
    context 'when diagnostics enabled with DSN provided' do
      before do
        allow(OT).to receive('d9s_enabled').and_return(true)
        allow(OT).to receive('conf').and_return(config.merge(
                                                  'diagnostics' => {
                                                    'sentry' => {
                                                      'frontend' => {
                                                        'dsn' => 'https://test-dsn@sentry.example.com/1',
                                                      },
                                                    },
                                                  },
                                                ))
      end

      it 'sets diagnostic variables when enabled and DSN provided' do
        vars = subject.serialized_data
        expect(vars['diagnostics']).to eq({
          'sentry' => {
            'dsn' => 'https://test-dsn@sentry.example.com/1',
          },
        })
        expect(vars['d9s_enabled']).to be true
      end
    end

    context 'when diagnostics disabled' do
      before do
        allow(OT).to receive('d9s_enabled').and_return(false)
        allow(OT).to receive('conf').and_return(config.merge(
                                                  'diagnostics' => {
                                                    'sentry' => {
                                                      'frontend' => {
                                                        'dsn' => nil,
                                                      },
                                                    },
                                                  },
                                                ))
      end

      it 'sets diagnostic to disabled when DSN not provided' do
        vars = subject.serialized_data
        expect(vars['d9s_enabled']).to be false
        expect(vars['diagnostics']).to eq({
          'sentry' => {
            'dsn' => nil,
          },
        })
      end
    end
  end

  context 'with security headers' do
    let(:rack_request) do
      super().tap do |req|
        req.env['ots.nonce'] = 'test-nonce-123'
      end
    end

    it 'includes CSP nonce when present' do
      expect(subject['nonce']).to eq('test-nonce-123')
    end
  end

  context 'with global banner' do
    before do
      allow(OT).to receive('global_banner').and_return({
        type: 'info',
        message: 'System maintenance scheduled',
      })
    end

    it 'includes global banner when present' do
      view = described_class.new(rack_request, session, customer)
      expect(view.serialized_data['global_banner']).to eq({
        type: 'info',
        message: 'System maintenance scheduled',
      })
    end
  end

  context 'with regions configuration' do
    let(:config) do
      super().merge(
        'site' => super()['site'].merge(
          'regions' => {
            'enabled' => true,
            'current_jurisdiction' => 'EU',
            'jurisdictions' => [
              {
                'identifier' => 'EU',
                'display_name' => 'European Union',
                'domain' => 'eu.example.com',
              },
            ],
          },
        ),
      )
    end

    it 'includes regions config when enabled' do
      expect(subject.serialized_data['regions_enabled']).to be true
      expect(subject.serialized_data['regions']).to include(
        'enabled' => true,
        'current_jurisdiction' => 'EU',
      )
    end

    context 'when regions disabled' do
      let(:config) do
        super().merge(
          'site' => super()['site'].merge(
            'regions' => { 'enabled' => false },
          ),
        )
      end

      it 'excludes regions data when disabled' do
        expect(subject.serialized_data['regions_enabled']).to be false
        expect(subject.serialized_data['regions']).to be_nil
      end
    end
  end

  context 'with required serialized_data keys' do
    let(:ensure_exist_keys) do
      %w[domains_enabled custid cust email customer_since]
    end

    it 'includes all required keys' do
      ensure_exist_keys.each do |key|
        expect(subject.serialized_data).to have_key(key),
          "Expected serialized_data to include #{key}"
      end
    end

    context 'with anonymous user' do
      let(:customer) do
        instance_double('V2::Customer',
          custid: 'anon',
          email: nil,
          anonymous?: true,
          planid: 'anonymous',
          created: Time.now.to_i,
          safe_dump: {
            "identifier" => "anon",
            "custid" => "anon",
            "role" => "customer",
            "verified" => nil,
            "last_login" => nil,
            "locale" => "",
            "updated" => nil,
            "created" => nil,
            "stripe_customer_id" => nil,
            "stripe_subscription_id" => nil,
            "stripe_checkout_email" => nil,
            "secrets_created" => "0",
            "secrets_burned" => "0",
            "secrets_shared" => "0",
            "emails_sent" => "0",
            "active" => false,
          },
          verified?: false,
          active?: false,
          role: 'anonymous')
      end

      let(:session) do
        instance_double('V2::Session',
          authenticated?: false,
          add_shrimp: nil,)
      end
    end
  end

  context 'with locale configuration' do
    let(:default_config) do
      {
        'internationalization' => {
          'enabled' => true,
          'default_locale' => 'en',
          'fallback_locale' => {
            'fr-CA' => %w[fr_CA fr_FR en],
            'fr' => %w[fr_FR fr_CA en],
            'fr-*' => ['fr_FR', 'en'],
            'default' => ['en'],
          },
          'locales' => %w[en fr_CA fr_FR],
        },
      }
    end

    # Test various locale scenarios
    shared_examples "locale initialization" do |locale, expected|
      let(:rack_request) do
        env = {
          'REMOTE_ADDR' => '127.0.0.1',
          'HTTP_HOST' => 'example.com',
          'rack.session' => {},
          'ots.locale' => locale,
        }

        request = instance_double('Rack::Request')
        allow(request).to receive(:env).and_return(env)
        allow(request).to receive(:nil?).and_return(false)
        # Ensure hash-like access to env
        allow(request).to receive(:[]) { |key| env[key] }
        request
      end

      # Create subject on demand to use the current rack_request
      subject { described_class.new(rack_request, session, customer) }

      it 'sets correct locale variables' do
        vars = subject.serialized_data
        expect(vars['locale']).to eq(expected[:locale])
      end
    end

    context 'with default locale' do
      include_examples "locale initialization", 'en', {
        locale: 'en',
        is_default: true,
      }
    end

    context 'with Canadian French locale' do
      include_examples "locale initialization", 'fr_CA', {
        locale: 'fr_CA',
        is_default: true,
      }
    end

    context 'with French locale' do
      include_examples "locale initialization", 'fr_FR', {
        locale: 'fr_FR',
        is_default: true,
      }
    end

    context 'with unsupported locale' do
      include_examples "locale initialization", 'es', {
        locale: 'es',
        is_default: true,
      }
    end

    context 'with nil locale' do
      let(:rack_request) do
        env = {'ots.locale' => nil}
        instance_double('Rack::Request', env: env)
      end

      it 'falls back to default locale' do
        vars = subject.serialized_data
        expect(vars['locale']).to eq('en')
      end
    end

    it "runs I18nSerializer" do
      serialized = subject.serialized_data
      expect(serialized).to include('locale', 'default_locale', 'supported_locales')
    end
  end
end
