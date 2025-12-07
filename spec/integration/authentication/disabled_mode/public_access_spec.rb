# spec/integration/authentication/disabled_mode/public_access_spec.rb
#
# frozen_string_literal: true

# Tests for disabled auth mode configuration.
# In disabled mode, authentication is completely off.

require 'spec_helper'

RSpec.describe 'Disabled Auth Mode', :disabled_auth_mode do
  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/auth_config'
  end

  describe 'mode configuration' do
    it 'reports disabled mode as active' do
      expect(Onetime.auth_config.mode).to eq('disabled')
    end

    it 'reports full mode as disabled' do
      expect(Onetime.auth_config.full_enabled?).to be false
    end

    it 'reports simple mode as disabled' do
      expect(Onetime.auth_config.simple_enabled?).to be false
    end

    it 'responds to disabled?' do
      expect(Onetime.auth_config.disabled?).to be true
    end
  end

  describe 'Auth::Database' do
    it 'returns nil for connection' do
      require 'auth/database'
      expect(Auth::Database.connection).to be_nil
    end
  end

  describe 'application behavior' do
    before(:all) do
      require 'onetime/middleware'
      require 'onetime/application/registry'
      # Reset and rebuild registry for disabled mode
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
    end

    it 'does not mount Auth app' do
      expect(Onetime::Application::Registry.mount_mappings.key?('/auth')).to be false
    end
  end

  describe 'Core::Application' do
    it 'is a valid Rack app' do
      require 'core/application'
      app = Core::Application.new
      expect(app).to respond_to(:call)
    end
  end
end
