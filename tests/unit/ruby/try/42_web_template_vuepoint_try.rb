# tests/unit/ruby/try/42_web_template_vuepoint_try.rb

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

require_relative './test_models'

# Use the default config file for tests
OT.boot! :test, false

@email = "tryouts+42+#{Time.now.to_i}@onetimesecret.com"
@cust = V1::Customer.create @email
@metadata = V2::Metadata.create
@secret = V2::Secret.create value: "This is a secret message"
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
view = Core::Views::VuePoint.new(@req, @sess, @cust, 'en', @metadata)
[view.req, view.sess, view.cust, view.locale]
#=> [@req, @sess, @cust, 'en']

## Correctly sets basic properties
view = Core::Views::VuePoint.new(@req, @sess, @cust, 'en', @metadata)
[view[:page_title], view[:frontend_host], view[:frontend_development], view[:no_cache]]
#=> ["Onetime Secret", "http://localhost:5173", false, false]

## Sets authentication status correctly
view = Core::Views::VuePoint.new(@req, @sess, @cust, 'en', @metadata)
authenticated_value = view[:jsvars][:authenticated]
authenticated_value
#=> true

## Handles unauthenticated user correctly
unauthenticated_sess = MockSession.new
def unauthenticated_sess.authenticated?; false; end
view = Core::Views::VuePoint.new(@req, unauthenticated_sess, V1::Customer.anonymous, 'en', @metadata)
authenticated_value = view[:jsvars][:authenticated]
authenticated_value
#=> false

## Sets locale correctly
view = Core::Views::VuePoint.new(@req, @sess, @cust, 'es', @metadata)
view.locale
#=> 'es'

## Falls back to default locale if not provided
view = Core::Views::VuePoint.new(@req, @sess, @cust, nil, @metadata)
view.locale
#=> 'en'

# Teardown
@secret.destroy!
@metadata.destroy!
@cust.destroy!
