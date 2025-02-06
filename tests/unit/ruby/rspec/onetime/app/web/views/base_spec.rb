# tests/unit/ruby/rspec/onetime/app/web/views/base_spec.rb

require_relative '../../../../spec_helper'

RSpec.describe Onetime::App::View do
  include_context "rack_test_context"
  include_context "view_test_context"

  subject { described_class.new(rack_request, session, customer) }

  describe '#initialize' do
    it 'sets basic template variables' do
      expect(subject[:description]).to eq('Test Description')
      expect(subject[:keywords]).to eq('test,keywords')
      expect(subject[:page_title]).to eq('Onetime Secret')
    end

    it 'initializes JavaScript variables' do
      vars = subject[:jsvars]
      expect(vars[:authenticated]).to be true
      expect(vars[:custid]).to eq('test@example.com')
      expect(vars[:email]).to eq('test@example.com')
      expect(vars[:shrimp]).to eq('test_shrimp')
    end

    it 'includes authentication configuration' do
      expect(subject[:jsvars][:authentication]).to eq({
        enabled: true,
        signup: true
      })
    end

    it 'includes secret options' do
      expect(subject[:jsvars][:secret_options]).to eq({
        default_ttl: 86400,
        ttl_options: [3600, 86400]
      })
    end

    context 'with development mode' do
      let(:config) do
        super().merge(
          development: {
            enabled: true,
            frontend_host: 'http://localhost:5173'
          }
        )
      end

      it 'sets development-specific variables' do
        expect(subject[:frontend_host]).to eq('http://localhost:5173')
        expect(subject[:frontend_development]).to be true
      end
    end

    context 'with anonymous user' do
      let(:customer) do
        instance_double('Customer',
          anonymous?: true,
          planid: 'anonymous',
          custid: nil
        )
      end

      it 'sets appropriate anonymous state' do
        vars = subject[:jsvars]
        expect(vars[:authenticated]).to be false
        expect(vars[:custid]).to be_nil
        expect(vars[:email]).to be_nil
      end
    end
  end

  describe '#add_message' do
    it 'adds info message to messages array' do
      subject.add_message('Test message')
      expect(subject.messages).to include({
        type: 'info',
        content: 'Test message'
      })
    end

    it 'adds error message to messages array' do
      subject.add_error('Error message')
      expect(subject.messages).to include({
        type: 'error',
        content: 'Error message'
      })
    end
  end

  context 'diagnostics configuration' do
    before do
      allow(Onetime).to receive(:with_diagnostics).and_yield
      allow(OT).to receive(:d9s).and_return(true)
      allow(OT).to receive(:conf).and_return(config.merge(
        services: {
          sentry: {
            frontend: {
              dsn: 'https://test-dsn@sentry.example.com/1'
            }
          }
        }
      ))
    end

    it 'sets diagnostic variables when enabled' do
      expect(subject[:jsvars][:d9s_enabled]).to be true
      expect(subject[:jsvars][:diagnostics]).to eq({
        sentry: {
          dsn: 'https://test-dsn@sentry.example.com/1',
        }
      })
    end
  end

  context 'security headers' do
    let(:rack_request) do
      super().tap do |req|
        allow(req.env).to receive(:fetch)
          .with('ots.nonce', nil)
          .and_return('test-nonce-123')
      end
    end

    it 'includes CSP nonce when present' do
      expect(subject[:nonce]).to eq('test-nonce-123')
    end
  end

  context 'global banner' do
    before do
      allow(OT).to receive(:global_banner).and_return({
        type: 'info',
        message: 'System maintenance scheduled'
      })
    end

    it 'includes global banner when present' do
      expect(subject[:jsvars][:global_banner]).to eq({
        type: 'info',
        message: 'System maintenance scheduled'
      })
    end
  end

  context 'regions configuration' do
    let(:config) do
      super().merge(
        site: super()[:site].merge(
          regions: {
            enabled: true,
            current_jurisdiction: 'EU',
            jurisdictions: [
              {
                identifier: 'EU',
                display_name: 'European Union',
                domain: 'eu.example.com'
              }
            ]
          }
        )
      )
    end

    it 'includes regions config when enabled' do
      expect(subject[:jsvars][:regions_enabled]).to be true
      expect(subject[:jsvars][:regions]).to include(
        enabled: true,
        current_jurisdiction: 'EU'
      )
    end

    context 'when regions disabled' do
      let(:config) do
        super().merge(
          site: super()[:site].merge(
            regions: { enabled: false }
          )
        )
      end

      it 'excludes regions data when disabled' do
        expect(subject[:jsvars][:regions_enabled]).to be false
        expect(subject[:jsvars][:regions]).to be_nil
      end
    end
  end

  context 'required jsvars keys' do
    let(:ensure_exist_keys) do
      [:domains_enabled, :custid, :cust, :email, :customer_since]
    end

    it 'includes all required keys' do
      ensure_exist_keys.each do |key|
        expect(subject[:jsvars]).to have_key(key),
          "Expected jsvars to include #{key}"
      end
    end

    context 'with anonymous user' do
      let(:customer) do
        instance_double('Customer',
          custid: 'anon',
          email: nil,
          anonymous?: true,
          planid: 'anonymous',
          created: Time.now.to_i,
          safe_dump: nil,
          verified?: false,
          active?: false,
          role: 'anonymous'
        )
      end

      let(:session) do
        instance_double('Session',
          authenticated?: false,
          add_shrimp: nil,
          get_messages: []
        )
      end

      it 'sets required keys to nil for anonymous users' do
        vars = subject[:jsvars]
        ensure_exist_keys.each do |key|
          expect(vars[key]).to be_nil,
            "Expected #{key} to be nil for anonymous user"
        end
      end
    end
  end
end
