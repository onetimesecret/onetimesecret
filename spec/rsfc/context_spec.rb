# spec/rsfc/context_spec.rb

require 'spec_helper'

RSpec.describe RSFC::Context do
  let(:mock_request) { double('request', env: { 'csrf_token' => 'test-csrf', 'nonce' => 'test-nonce' }) }
  let(:mock_session) { RSFC::Adapters::AuthenticatedSession.new(id: 'session123', created_at: Time.now) }
  let(:mock_user) { RSFC::Adapters::AuthenticatedAuth.new(id: 456, name: 'Test User', theme: 'dark') }
  let(:business_data) { { page_title: 'Test Page', content: 'Hello World' } }

  describe '#initialize' do
    subject { described_class.new(mock_request, mock_session, mock_user, 'en', business_data: business_data) }

    it 'initializes with provided parameters' do
      expect(subject.req).to eq(mock_request)
      expect(subject.sess).to eq(mock_session)
      expect(subject.cust).to eq(mock_user)
      expect(subject.locale).to eq('en')
      expect(subject.business_data).to eq(business_data)
    end

    it 'uses default values when not provided' do
      context = described_class.new(nil)
      expect(context.sess).to be_a(RSFC::Adapters::AnonymousSession)
      expect(context.cust).to be_a(RSFC::Adapters::AnonymousAuth)
      expect(context.locale).to eq('en')
    end

    it 'freezes the context after creation' do
      expect(subject).to be_frozen
    end
  end

  describe '#get' do
    subject { described_class.new(mock_request, mock_session, mock_user, 'en', business_data: business_data) }

    it 'retrieves runtime data' do
      expect(subject.get('csrf_token')).to eq('test-csrf')
      expect(subject.get('nonce')).to eq('test-nonce')
    end

    it 'retrieves business data' do
      expect(subject.get('page_title')).to eq('Test Page')
      expect(subject.get('content')).to eq('Hello World')
    end

    it 'retrieves computed data' do
      expect(subject.get('authenticated')).to be(true)
      expect(subject.get('theme_class')).to eq('theme-dark')
    end

    it 'supports dot notation' do
      nested_data = { user: { profile: { name: 'John' } } }
      context = described_class.new(nil, nil, nil, 'en', business_data: nested_data)
      expect(context.get('user.profile.name')).to eq('John')
    end

    it 'returns nil for non-existent variables' do
      expect(subject.get('non_existent')).to be_nil
    end
  end

  describe '#has_variable?' do
    subject { described_class.new(mock_request, mock_session, mock_user, 'en', business_data: business_data) }

    it 'returns true for existing variables' do
      expect(subject.has_variable?('page_title')).to be(true)
      expect(subject.has_variable?('csrf_token')).to be(true)
    end

    it 'returns false for non-existent variables' do
      expect(subject.has_variable?('non_existent')).to be(false)
    end
  end

  describe '#available_variables' do
    subject { described_class.new(nil, nil, nil, 'en', business_data: { user: { name: 'Test' } }) }

    it 'returns list of available variable paths' do
      variables = subject.available_variables
      expect(variables).to include('user')
      expect(variables).to include('user.name')
      expect(variables).to include('app_environment')
      expect(variables).to include('authenticated')
    end
  end

  describe '.for_view' do
    it 'creates context with business data' do
      context = described_class.for_view(mock_request, mock_session, mock_user, 'es', test_data: 'value')
      expect(context.locale).to eq('es')
      expect(context.get('test_data')).to eq('value')
    end
  end

  describe '.minimal' do
    it 'creates minimal context for testing' do
      context = described_class.minimal(business_data: { test: 'data' })
      expect(context.req).to be_nil
      expect(context.sess).to be_a(RSFC::Adapters::AnonymousSession)
      expect(context.cust).to be_a(RSFC::Adapters::AnonymousAuth)
      expect(context.locale).to eq('en')
      expect(context.get('test')).to eq('data')
    end
  end

  describe 'with custom configuration' do
    let(:custom_config) do
      config = RSFC::Configuration.new
      config.default_locale = 'fr'
      config.app_environment = 'staging'
      config.features = { custom_feature: true }
      config
    end

    subject { described_class.new(nil, nil, nil, nil, config: custom_config) }

    it 'uses custom configuration' do
      expect(subject.locale).to eq('fr')
      expect(subject.get('app_environment')).to eq('staging')
      expect(subject.get('features.custom_feature')).to be(true)
    end
  end
end