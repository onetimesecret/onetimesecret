# spec/integration/simple/auth_mode_spec.rb
#
# frozen_string_literal: true

# Integration tests for simple authentication mode configuration
#
# These tests verify that in simple mode:
# - Auth app is NOT mounted
# - Core app is mounted at root
# - Full auth features are disabled

require_relative '../integration_spec_helper'

RSpec.describe 'Simple Mode Configuration', type: :integration do
  include Rack::Test::Methods

  def app
    @simple_app ||= begin
      # Prepare registry with simple mode
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    # Force app loading by calling app method
    app
  end

  it 'runs in simple mode' do
    expect(Onetime.auth_config.mode).to eq('simple')
  end

  it 'has full mode disabled' do
    expect(Onetime.auth_config.full_enabled?).to be false
  end

  it 'does not mount Auth app' do
    expect(Onetime::Application::Registry.mount_mappings.key?('/auth')).to be false
  end

  it 'mounts Core app at root' do
    expect(Onetime::Application::Registry.mount_mappings.key?('/')).to be true
  end
end
