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

    def initialize(mode, **options)
      @mode = mode.to_s
      @hardening_enabled = options.fetch(:hardening_enabled, true)
      @active_sessions_enabled = options.fetch(:active_sessions_enabled, true)
      @remember_me_enabled = options.fetch(:remember_me_enabled, true)
      @verify_account_enabled = options.fetch(:verify_account_enabled, false)  # Disabled in test by default
      @mfa_enabled = options.fetch(:mfa_enabled, true)
      @email_auth_enabled = options.fetch(:email_auth_enabled, false)
      @webauthn_enabled = options.fetch(:webauthn_enabled, false)
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

    # Predicate methods matching AuthConfig interface
    def hardening_enabled?
      @hardening_enabled
    end

    def active_sessions_enabled?
      @active_sessions_enabled
    end

    def remember_me_enabled?
      @remember_me_enabled
    end

    def verify_account_enabled?
      @verify_account_enabled
    end

    def mfa_enabled?
      @mfa_enabled
    end

    def email_auth_enabled?
      @email_auth_enabled
    end

    def webauthn_enabled?
      @webauthn_enabled
    end

    # DEPRECATED: Forwards to new methods for backward compatibility
    def security_features_enabled?
      hardening_enabled? && active_sessions_enabled? && remember_me_enabled?
    end

    def magic_links_enabled?
      email_auth_enabled?
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
        'same_site' => 'lax'
      }
    end

    def reload!
      self
    end
  end

  # Mutex for thread-safe singleton method modification
  @install_mutex = Mutex.new

  # Install mock for a given mode - replaces Onetime.auth_config at module level
  # Returns the mock instance for further configuration if needed
  #
  # Thread safety: Uses mutex to prevent race conditions when parallel tests
  # attempt to modify Onetime.auth_config singleton method simultaneously.
  def self.install_mock(mode, context_metadata, **options)
    @install_mutex.synchronize do
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
  end

  # Restore original auth_config method
  # Thread safety: Uses same mutex as install_mock to prevent race conditions
  def self.restore_original(context_metadata)
    @install_mutex.synchronize do
      context_metadata[:auth_mode_current_mock] = nil
      context_metadata[:auth_mode_current_mode] = nil

      # Only restore if we have the real original stored in this context
      original_method = context_metadata[:auth_mode_original_method]
      return unless original_method

      begin
        Onetime.define_singleton_method(:auth_config, original_method)
      rescue => e
        warn "Failed to restore original auth_config method: #{e.message}"
        raise
      ensure
        context_metadata[:auth_mode_original_method] = nil
      end
    end
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
    AuthModeHelpers.reset_database_connection!
    AuthModeHelpers.restore_original(self.class.metadata)
  end

  # Simple auth mode - install mock BEFORE any setup runs
  config.before(:context, :simple_auth_mode) do
    AuthModeHelpers.install_mock('simple', self.class.metadata)
  end

  config.after(:context, :simple_auth_mode) do
    AuthModeHelpers.reset_database_connection!
    AuthModeHelpers.restore_original(self.class.metadata)
  end

  # Disabled auth mode - install mock BEFORE any setup runs
  config.before(:context, :disabled_auth_mode) do
    AuthModeHelpers.install_mock('disabled', self.class.metadata)
  end

  config.after(:context, :disabled_auth_mode) do
    AuthModeHelpers.reset_database_connection!
    AuthModeHelpers.restore_original(self.class.metadata)
  end
end
