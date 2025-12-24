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

    def database_url_migrations
      # In tests, migration connection is same as regular connection
      database_url
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
        'key' => 'onetime.session',  # Cookie name - REQUIRED
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
  def self.install_mock(mode, context_metadata, **options)
    # Store the REAL original method in the context metadata (not module-level)
    # This prevents leaks between test contexts
    unless context_metadata[:auth_mode_original_method]
      if Onetime.respond_to?(:auth_config) && !Onetime.method(:auth_config).owner.equal?(Onetime.singleton_class)
        context_metadata[:auth_mode_original_method] = Onetime.method(:auth_config)
      end
    end

    mock = MockAuthConfig.new(mode, **options)
    context_metadata[:auth_mode_current_mock] = mock
    context_metadata[:auth_mode_current_mode] = mode
    Onetime.define_singleton_method(:auth_config) { mock }
    mock
  end

  # Restore original auth_config method
  def self.restore_original(context_metadata)
    context_metadata[:auth_mode_current_mock] = nil
    context_metadata[:auth_mode_current_mode] = nil

    # Only restore if we have the real original stored in this context
    original_method = context_metadata[:auth_mode_original_method]
    return unless original_method

    Onetime.define_singleton_method(:auth_config, original_method)
    context_metadata[:auth_mode_original_method] = nil
  end

  # Get current mock mode (useful for debugging)
  def self.current_mode(context_metadata)
    context_metadata[:auth_mode_current_mode]
  end

  # Check if a mock is currently installed
  def self.mock_installed?(context_metadata)
    !context_metadata[:auth_mode_current_mock].nil?
  end

  # Reset cached database connection (call before tests that need fresh connection)
  def self.reset_database_connection!
    return unless defined?(Auth::Database)

    # Use the new reset_connection! method if available (supports LazyConnection cleanup)
    if Auth::Database.respond_to?(:reset_connection!)
      Auth::Database.reset_connection!
    else
      Auth::Database.instance_variable_set(:@connection, nil)
    end
  end
end

RSpec.configure do |config|
  # Full auth mode - install mock BEFORE any setup runs
  config.before(:context, :full_auth_mode) do
    AuthModeHelpers.install_mock('full', self.class.metadata)
  end

  config.after(:context, :full_auth_mode) do
    AuthModeHelpers.restore_original(self.class.metadata)
  end

  # Simple auth mode - install mock BEFORE any setup runs
  config.before(:context, :simple_auth_mode) do
    AuthModeHelpers.install_mock('simple', self.class.metadata)
  end

  config.after(:context, :simple_auth_mode) do
    AuthModeHelpers.restore_original(self.class.metadata)
  end

  # Disabled auth mode - install mock BEFORE any setup runs
  config.before(:context, :disabled_auth_mode) do
    AuthModeHelpers.install_mock('disabled', self.class.metadata)
  end

  config.after(:context, :disabled_auth_mode) do
    AuthModeHelpers.restore_original(self.class.metadata)
  end
end
