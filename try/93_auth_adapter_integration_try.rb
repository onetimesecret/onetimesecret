# try/93_auth_adapter_integration_try.rb

require_relative 'test_helpers'
require_relative '../app/services/auth/basic_auth_adapter'
require_relative '../app/services/auth/rodauth_adapter'
require_relative '../app/services/auth/adapter_factory'
require 'rack/test'
require 'bcrypt'

OT.boot! :test, false

# Create a mock environment with Rack session
@mock_env = {
  'rack.session' => {}
}

# Create test customer with hashed password
@test_email = "test_#{Time.now.to_i}@example.com"
@test_password = "secure_password_123"
@test_custid = "cust_#{Time.now.to_i}"

# Create customer with passphrase
@test_customer = V2::Customer.new(@test_custid)
@test_customer.email = @test_email
@test_customer.update_passphrase(@test_password)
@test_customer.save

## AdapterFactory creates BasicAuthAdapter in basic mode
# Config is already set in test environment, just check current state
adapter = Auth::AdapterFactory.create(@mock_env)
# Since external auth is not configured in test, should be BasicAuthAdapter
adapter.class == Auth::BasicAuthAdapter
#=> true

## AdapterFactory reports available features correctly for basic mode
features = Auth::AdapterFactory.available_features
# In test mode, external is not enabled so should be basic
features[:mode] == 'basic' && features[:external_service] == false
#=> true

## BasicAuthAdapter authenticates valid credentials
adapter = Auth::BasicAuthAdapter.new(@mock_env)
result = adapter.authenticate(@test_email, @test_password)
result[:success] == true && result[:identity_id] == @test_custid
#=> true

## BasicAuthAdapter sets session on successful authentication
@mock_env['rack.session'].clear
adapter = Auth::BasicAuthAdapter.new(@mock_env)
adapter.authenticate(@test_email, @test_password)
session = @mock_env['rack.session']
session['authenticated'] == true && session['identity_id'] == @test_custid
#=> true

## BasicAuthAdapter rejects invalid password
adapter = Auth::BasicAuthAdapter.new(@mock_env)
result = adapter.authenticate(@test_email, 'wrong_password')
result[:success] == false && result[:error] == 'Invalid email or password'
#=> true

## BasicAuthAdapter rejects non-existent email
adapter = Auth::BasicAuthAdapter.new(@mock_env)
result = adapter.authenticate('nonexistent@example.com', @test_password)
result[:success] == false && result[:error] == 'Invalid email or password'
#=> true

## BasicAuthAdapter current_identity returns session data when authenticated
@mock_env['rack.session'].clear
adapter = Auth::BasicAuthAdapter.new(@mock_env)
adapter.authenticate(@test_email, @test_password)
identity = adapter.current_identity
identity[:identity_id] == @test_custid && identity[:email] == @test_email
#=> true

## BasicAuthAdapter current_identity returns nil when not authenticated
@mock_env['rack.session'].clear
adapter = Auth::BasicAuthAdapter.new(@mock_env)
identity = adapter.current_identity
identity.nil?
#=> true

## BasicAuthAdapter authenticated? returns correct status
@mock_env['rack.session'].clear
adapter = Auth::BasicAuthAdapter.new(@mock_env)
authenticated_before = adapter.authenticated?
adapter.authenticate(@test_email, @test_password)
authenticated_after = adapter.authenticated?
!authenticated_before && authenticated_after
#=> true

## BasicAuthAdapter logout clears session
@mock_env['rack.session'].clear
adapter = Auth::BasicAuthAdapter.new(@mock_env)
adapter.authenticate(@test_email, @test_password)
adapter.logout
@mock_env['rack.session'].empty?
#=> true

## RodauthAdapter falls back to BasicAuth behavior (placeholder)
@mock_env['rack.session'].clear
adapter = Auth::RodauthAdapter.new(@mock_env)
result = adapter.authenticate(@test_email, @test_password)
session = @mock_env['rack.session']
result[:success] == true && session['auth_method'] == 'rodauth'
#=> true

## RodauthAdapter sets external_service flag in session
@mock_env['rack.session'].clear
adapter = Auth::RodauthAdapter.new(@mock_env)
adapter.authenticate(@test_email, @test_password)
@mock_env['rack.session']['external_service'] == true
#=> true

## RodauthAdapter current_identity includes auth_method
@mock_env['rack.session'].clear
adapter = Auth::RodauthAdapter.new(@mock_env)
adapter.authenticate(@test_email, @test_password)
identity = adapter.current_identity
identity[:auth_method] == 'rodauth' && identity[:external_service] == true
#=> true

# Clean up test customer
@test_customer.destroy! if @test_customer
Familia.dbclient.flushdb if Familia.dbclient.dbsize < 100