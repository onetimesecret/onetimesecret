# try/integration/web/template_vuepoint_try.rb
#
# frozen_string_literal: true

# These tryouts test the VuePoint view functionality in the Onetime application,
# with a focus on the initialization process via the request object.
# They cover:
#
# 1. Creating and initializing a VuePoint view from request
# 2. Testing authentication status based on strategy_result
# 3. Verifying locale handling
#
# These tests ensure that the VuePoint view correctly handles different scenarios
# and properly initializes based on the request environment.

require 'rack/request'
require 'rack/mock'
require 'ostruct'

require_relative '../../support/test_helpers'
require_relative '../../support/test_models'
require_relative '../../support/test_logic'

require 'core/views'

OT.boot! :test, false

@email = "tryouts+42+#{Familia.now.to_i}@onetimesecret.com"
@cust = Onetime::Customer.create!(email: @email)
@metadata, @secret = Onetime::Metadata.spawn_pair(
  @cust.identifier,
  3600,
  "This is a secret message"
)

# Helper to create a properly configured mock request
def create_mock_request(locale: 'en', user: nil, authenticated: true)
  session = { 'test_key' => 'test_value' }
  strategy_result = OpenStruct.new(
    session: session,
    user: user || Onetime::Customer.anonymous,
    authenticated?: authenticated
  )

  env = Rack::MockRequest.env_for('http://example.com/')
  env['otto.strategy_result'] = strategy_result
  env['otto.locale'] = locale
  env['onetime.nonce'] = 'test-nonce'
  env['rack.session'] = session

  Rack::Request.new(env)
end

## Can create a VuePoint view from request
req = create_mock_request(locale: 'en', user: @cust)
view = Core::Views::VuePoint.new(req)
[view.req.class, view.locale.class]
#=> [Rack::Request, String]

## View extracts locale from request
req = create_mock_request(locale: 'en', user: @cust)
view = Core::Views::VuePoint.new(req)
view.locale
#=> 'en'

## View extracts customer from strategy_result
req = create_mock_request(locale: 'en', user: @cust)
view = Core::Views::VuePoint.new(req)
view.cust.email
#=> @cust.email

## Sets authentication status correctly for authenticated user
req = create_mock_request(locale: 'en', user: @cust, authenticated: true)
view = Core::Views::VuePoint.new(req)
view.serialized_data['authenticated']
#=> true

## Handles unauthenticated user correctly
req = create_mock_request(locale: 'en', user: Onetime::Customer.anonymous, authenticated: false)
view = Core::Views::VuePoint.new(req)
view.serialized_data['authenticated']
#=> false

## Sets locale correctly from request
req = create_mock_request(locale: 'es', user: @cust)
view = Core::Views::VuePoint.new(req)
view.locale
#=> 'es'

# Teardown
@secret.destroy!
@metadata.destroy!
@cust.destroy!
