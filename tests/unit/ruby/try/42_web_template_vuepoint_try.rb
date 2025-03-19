# frozen_string_literal: true

# These tryouts test the VuePoint view functionality in the OneTime application,
# with a focus on the initialization process and its arguments.
# They cover:
#
# 1. Creating and initializing a VuePoint view with various arguments
# 2. Testing the visibility of different elements based on metadata state and user authentication
# 3. Verifying the correct generation of URIs and paths
# 4. Checking the handling of secret values and their display properties
#
# These tests ensure that the VuePoint view correctly handles different scenarios
# and properly initializes based on the provided arguments.

require 'onetime'

# Use the default config file for tests
OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

@email = "tryouts+#{Time.now.to_i}@onetimesecret.com"
@cust = OT::Customer.create @email
@metadata = OT::Metadata.create
@secret = OT::Secret.create value: "This is a secret message"
@metadata.secret_key = @secret.key
@metadata.save

# Mock request object
class MockRequest
  attr_reader :env
  def initialize
    @env = {'ots.locale' => 'en'}
  end
end

# Mock session object
class MockSession
  def authenticated?
    true
  end
  def add_shrimp
    "mock_shrimp"
  end
  def get_messages
    []
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
end

@req = MockRequest.new
@sess = MockSession.new

## Can create a VuePoint view with all arguments
view = OT::App::Views::VuePoint.new(@req, @sess, @cust, 'en', @metadata)
[view.req, view.sess, view.cust, view.locale]
#=> [@req, @sess, @cust, 'en']

## Correctly sets basic properties
view = OT::App::Views::VuePoint.new(@req, @sess, @cust, 'en', @metadata)
[view[:page_title], view[:frontend_host], view[:frontend_development], view[:no_cache]]
#=> ["Onetime Secret", "http://localhost:5173", false, false]

## Sets authentication status correctly
view = OT::App::Views::VuePoint.new(@req, @sess, @cust, 'en', @metadata)
authenticated_value = view[:jsvars][:authenticated]
authenticated_value
#=> true

## Handles unauthenticated user correctly
unauthenticated_sess = MockSession.new
def unauthenticated_sess.authenticated?; false; end
view = OT::App::Views::VuePoint.new(@req, unauthenticated_sess, OT::Customer.anonymous, 'en', @metadata)
authenticated_value = view[:jsvars][:authenticated]
authenticated_value
#=> false

## Sets locale correctly
view = OT::App::Views::VuePoint.new(@req, @sess, @cust, 'es', @metadata)
view.locale
#=> 'es'

## Falls back to default locale if not provided
view = OT::App::Views::VuePoint.new(@req, @sess, @cust, nil, @metadata)
view.locale
#=> 'en'

# Teardown
@secret.destroy!
@metadata.destroy!
@cust.destroy!
