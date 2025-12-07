# spec/integration/authentication/simple_mode/adapter_spec.rb
#
# frozen_string_literal: true

# Tests for simple auth mode configuration.
# Note: Auth::Application cannot be loaded in simple mode because Rodauth
# requires a database connection. These tests verify the mode configuration
# and basic app behavior.

require 'spec_helper'
require 'rack/test'

RSpec.describe 'Simple Auth Mode', :simple_auth_mode do
  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/auth_config'
    require 'onetime/middleware'
    require 'onetime/application/registry'
    Onetime::Application::Registry.prepare_application_registry
  end

  describe 'mode configuration' do
    it 'reports simple mode as active' do
      expect(Onetime.auth_config.mode).to eq('simple')
    end

    it 'reports simple mode enabled' do
      expect(Onetime.auth_config.simple_enabled?).to be true
    end

    it 'reports full mode as disabled' do
      expect(Onetime.auth_config.full_enabled?).to be false
    end

    it 'returns nil for database connection' do
      require 'auth/database'
      expect(Auth::Database.connection).to be_nil
    end
  end

  describe 'application registry' do
    it 'has Core app registered at root' do
      expect(Onetime::Application::Registry.mount_mappings['/']).not_to be_nil
    end

    it 'can instantiate Core app' do
      core_app_class = Onetime::Application::Registry.mount_mappings['/']
      core_app = core_app_class.new
      expect(core_app).to be_a(Core::Application)
    end

    it 'Auth app is NOT mounted in simple mode' do
      # In simple mode, the auth app shouldn't be mounted
      # (or if mounted, should handle requests gracefully)
      auth_mapping = Onetime::Application::Registry.mount_mappings['/auth']
      expect(auth_mapping).to be_nil
    end
  end

  describe 'Core::Application' do
    include Rack::Test::Methods

    def app
      Core::Application.new
    end

    it 'responds to call (is a valid Rack app)' do
      expect(app).to respond_to(:call)
    end

    it 'homepage returns 200' do
      get '/'
      expect(last_response.status).to eq(200)
    end
  end
end
