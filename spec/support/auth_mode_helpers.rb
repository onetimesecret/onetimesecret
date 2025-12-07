# spec/support/auth_mode_helpers.rb
#
# frozen_string_literal: true

# Helper module for configuring authentication mode in specs via AuthConfig mocks.
#
# The mock is set up in before(:context) so it's in place BEFORE Onetime.boot! runs.
# This ensures the entire application stack sees the mocked auth mode.
#
# Usage in spec files:
#
#   RSpec.describe 'My Test', :full_auth_mode do
#     before(:all) do
#       Onetime.boot! :test  # This will use the mocked auth_config
#     end
#     # ...
#   end
#
module AuthModeHelpers
  VALID_MODES = %w[simple full disabled].freeze

  # Mock object that responds to all AuthConfig methods
  class MockAuthConfig
    attr_reader :mode
    attr_accessor :mfa_enabled, :magic_links_enabled, :security_features_enabled

    def initialize(mode, **options)
      @mode = mode.to_s
      @mfa_enabled = options.fetch(:mfa_enabled, true)
      @magic_links_enabled = options.fetch(:magic_links_enabled, false)
      @security_features_enabled = options.fetch(:security_features_enabled, true)
    end

    def full_enabled?
      @mode == 'full'
    end

    def simple_enabled?
      @mode == 'simple'
    end

    def disabled?
      @mode == 'disabled'
    end

    def database_url
      @mode == 'full' ? 'sqlite::memory:' : nil
    end

    def full
      @mode == 'full' ? { 'database_url' => 'sqlite::memory:' } : {}
    end

    def simple
      {}
    end

    def session
      {
        'secret' => 'test-secret-minimum-64-characters-for-secure-sessions-testing',
        'expire_after' => 86400,
        'secure' => false,
        'httponly' => true,
        'same_site' => 'strict'
      }
    end

    def reload!
      self
    end
  end

  # Install mock for a given mode - replaces Onetime.auth_config at module level
  # Returns the mock instance for further configuration if needed
  def self.install_mock(mode, **options)
    # Capture the REAL original method only once (not a previously installed mock)
    unless @real_original_method
      if Onetime.respond_to?(:auth_config) && !Onetime.method(:auth_config).owner.equal?(Onetime.singleton_class)
        @real_original_method = Onetime.method(:auth_config)
      end
    end

    mock = MockAuthConfig.new(mode, **options)
    @current_mock = mock
    @current_mode = mode
    Onetime.define_singleton_method(:auth_config) { mock }
    mock
  end

  # Restore original auth_config method
  def self.restore_original
    @current_mock = nil
    @current_mode = nil

    # Only restore if we have the real original
    return unless @real_original_method

    Onetime.define_singleton_method(:auth_config, @real_original_method)
  end

  # Get current mock mode (useful for debugging)
  def self.current_mode
    @current_mode
  end

  # Check if a mock is currently installed
  def self.mock_installed?
    !@current_mock.nil?
  end

  # Reset cached database connection (call before tests that need fresh connection)
  def self.reset_database_connection!
    return unless defined?(Auth::Database)

    Auth::Database.instance_variable_set(:@connection, nil)
  end
end

RSpec.configure do |config|
  # Full auth mode - install mock BEFORE any setup runs
  config.before(:context, :full_auth_mode) do
    AuthModeHelpers.install_mock('full')
  end

  config.after(:context, :full_auth_mode) do
    AuthModeHelpers.restore_original
  end

  # Simple auth mode - install mock BEFORE any setup runs
  config.before(:context, :simple_auth_mode) do
    AuthModeHelpers.install_mock('simple')
  end

  config.after(:context, :simple_auth_mode) do
    AuthModeHelpers.restore_original
  end

  # Disabled auth mode - install mock BEFORE any setup runs
  config.before(:context, :disabled_auth_mode) do
    AuthModeHelpers.install_mock('disabled')
  end

  config.after(:context, :disabled_auth_mode) do
    AuthModeHelpers.restore_original
  end
end
