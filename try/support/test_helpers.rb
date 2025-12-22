# try/support/test_helpers.rb
#
# frozen_string_literal: true
#
# Common test helpers for Tryouts tests.
#
# IMPORTANT: This file must be required BEFORE loading config.ru in integration
# tests that use Rack::MockRequest. It sets up the test environment properly.

# Force RACK_ENV=test to disable Rack::Lint middleware (which requires all
# HTTP_* env vars to be strings - incompatible with Rack::MockRequest defaults).
# Must use = not ||= because tryouts framework may set RACK_ENV=development.
ENV['RACK_ENV'] = 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..', '..')).freeze

# Set test database URL BEFORE config loads - use port 2121 to avoid conflicts
# with development Redis. This must be set before config.test.yaml is loaded via
# ERB since it checks ENV['VALKEY_URL'] || ENV['REDIS_URL'] || default.
#
# IMPORTANT: Override both VALKEY_URL and REDIS_URL to prevent production values
# from .env file or CI environment leaking into tests.
ENV['VALKEY_URL'] = 'valkey://127.0.0.1:2121/0'
ENV['REDIS_URL'] = 'redis://127.0.0.1:2121/0'

project_root = ENV['ONETIME_HOME']
app_root = File.join(project_root, '/apps').freeze

$LOAD_PATH.unshift(File.join(app_root))

require 'onetime'
require 'onetime/models'

OT::Config.path = File.join(project_root, 'spec', 'config.test.yaml')

# NOTE: Database logging is now handled by the SetupDatabaseLogging initializer
# which runs automatically during OT.boot!. Set DEBUG_DATABASE=1 to enable.

# Temporarily set an environment variable within a block, restoring it after.
# @param key [String] The environment variable name
# @param value [String] The value to set
# @yield The block to execute with the modified environment
# @return The return value of the block
def with_env(key, value)
  original = ENV[key]
  ENV[key] = value
  yield
ensure
  ENV[key] = original
end

def generate_random_email
  # Generate a random username
  username = (0...8).map { ('a'..'z').to_a[rand(26)] }.join
  # Define a domain
  domain = "onetimesecret.com"
  # Combine to form an email address
  "#{username}@#{domain}"
end

# Generate a unique test email with file context and entropy
# @param prefix [String] Optional prefix to identify test context (e.g., "secrets", "auth")
# @return [String] A unique email address for testing
def generate_unique_test_email(prefix = "tryouts")
  timestamp = Familia.now.to_i
  entropy = SecureRandom.hex(4)
  "#{prefix}+#{timestamp}+#{entropy}@onetimesecret.com"
end

# Mock StrategyResult for testing Logic classes
# Logic::Base now expects a StrategyResult object instead of separate session/customer
class MockStrategyResult
  attr_reader :session, :user, :auth_method, :metadata

  def initialize(session: nil, user: nil, auth_method: 'anonymous', metadata: {})
    @session = session || {}
    @user = user
    @auth_method = auth_method
    @metadata = metadata || {}
  end

  # Create an anonymous (unauthenticated) result
  def self.anonymous(metadata: {})
    new(
      session: {},
      user: nil,
      auth_method: 'anonymous',
      metadata: metadata
    )
  end

  # Check if the request has an authenticated user in session
  def authenticated?
    !user.nil?
  end

  # Check if authentication strategy just executed and succeeded
  def auth_attempt_succeeded?
    authenticated? && auth_method.to_s != 'anonymous'
  end

  # Check if the request is anonymous (no user in session)
  def anonymous?
    user.nil?
  end

  # Check if the user has a specific role
  def has_role?(role)
    return false unless authenticated?

    # Try user model methods first, fall back to hash access for backward compatibility
    if user.respond_to?(:role)
      user.role.to_s == role.to_s
    elsif user.respond_to?(:has_role?)
      user.has_role?(role)
    elsif user.is_a?(Hash)
      user_role = user[:role] || user['role']
      user_role.to_s == role.to_s
    else
      false
    end
  end

  # Check if the user has a specific permission
  def has_permission?(permission)
    return false unless authenticated?

    # Try user model methods first, fall back to hash access for backward compatibility
    if user.respond_to?(:has_permission?)
      user.has_permission?(permission)
    elsif user.respond_to?(:permissions)
      permissions = user.permissions || []
      permissions = [permissions] unless permissions.is_a?(Array)
      permissions.map(&:to_s).include?(permission.to_s)
    elsif user.is_a?(Hash)
      permissions = user[:permissions] || user['permissions'] || []
      permissions = [permissions] unless permissions.is_a?(Array)
      permissions.map(&:to_s).include?(permission.to_s)
    else
      false
    end
  end

  # Check if the user has any of the specified roles
  def has_any_role?(*roles)
    roles.flatten.any? { |role| has_role?(role) }
  end

  # Check if the user has any of the specified permissions
  def has_any_permission?(*permissions)
    permissions.flatten.any? { |permission| has_permission?(permission) }
  end

  # Get user ID from various possible locations
  def user_id
    return nil unless authenticated?

    # Try user model methods first, fall back to hash access and session
    if user.respond_to?(:id)
      user.id
    elsif user.respond_to?(:user_id)
      user.user_id
    elsif user.is_a?(Hash)
      user[:id] || user['id'] || user[:user_id] || user['user_id']
    end || session[:user_id] || session['user_id']
  end

  # Get user name from various possible locations
  def user_name
    return nil unless authenticated?

    # Try user model methods first, fall back to hash access
    if user.respond_to?(:name)
      user.name
    elsif user.respond_to?(:username)
      user.username
    elsif user.is_a?(Hash)
      user[:name] || user['name'] || user[:username] || user['username']
    end
  end

  # Get session ID from various possible locations
  def session_id
    session[:id] || session['id'] || session[:session_id] || session['session_id']
  end

  # Get all user roles as an array
  def roles
    return [] unless authenticated?

    roles_data = user[:roles] || user['roles']
    if roles_data.is_a?(Array)
      roles_data.map(&:to_s)
    elsif roles_data
      [roles_data.to_s]
    else
      role = user[:role] || user['role']
      role ? [role.to_s] : []
    end
  end

  # Get all user permissions as an array
  def permissions
    return [] unless authenticated?

    perms = user[:permissions] || user['permissions'] || []
    perms = [perms] unless perms.is_a?(Array)
    perms.map(&:to_s)
  end

  # Create a string representation for debugging
  def inspect
    if authenticated?
      "#<MockStrategyResult authenticated user=#{user_name || user_id} roles=#{roles} method=#{auth_method}>"
    else
      "#<MockStrategyResult anonymous method=#{auth_method}>"
    end
  end

  # Get user context - a hash containing user-specific information and metadata
  def user_context
    if authenticated?
      case auth_method
      when 'session'
        { user_id: user_id, session: session }
      else
        metadata
      end
    else
      case auth_method
      when 'anonymous'
        {}
      else
        metadata
      end
    end
  end

  # Create a hash representation
  def to_h
    {
      session: session,
      user: user,
      auth_method: auth_method,
      metadata: metadata,
      authenticated: authenticated?,
      auth_attempt_succeeded: auth_attempt_succeeded?,
      user_id: user_id,
      user_name: user_name,
      roles: roles,
      permissions: permissions
    }
  end
end

# Legacy MockSession for backward compatibility
# Use MockStrategyResult for new Logic tests
class MockSession
  def authenticated?
    true
  end

  def short_identifier
    "mock_short_identifier"
  end

  def id
    @id ||= Struct.new(:public_id).new("mock_session_id")
  end

  def ipaddress
    "mock_ipaddress"
  end

  def add_shrimp
    "mock_shrimp"
  end

  def get_error_messages
    []
  end

  def get_info_messages
    []
  end

  def get_form_fields!
    {}
  end

  def [](key)
    nil
  end

  def []=(key, value)
    value
  end
end

# Test Request Helpers
#
# Extends Rack::Request with Otto middleware methods for testing controllers
# that depend on Otto extensions like req.locale
module TestRequestHelpers
  # Get locale from Otto middleware or fallback to default
  #
  # Mimics Onetime::Application::RequestHelpers#locale behavior
  # @return [String] Locale code (e.g., 'en', 'es', 'fr')
  def locale
    env['otto.locale'] || OT.default_locale
  end
end

# Disable billing by default for all Tryouts tests
# This ensures billing_enabled? returns false, giving full standalone entitlements.
# Tests that need billing enabled should use BillingTestHelpers.with_billing_enabled
require_relative 'billing_helpers'
BillingTestHelpers.disable_billing!
