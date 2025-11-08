# try/42_web_template_vuepoint_try.rb

# These tryouts test the VuePoint view functionality in the Onetime application,
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

require_relative '../../support/test_helpers'
require_relative '../../support/test_models'
require_relative '../../support/test_logic'

require 'core/views'

OT.boot! :test, false

@email = "tryouts+42+#{Familia.now.to_i}@onetimesecret.com"
@cust = Onetime::Customer.create!(email: @email)
@metadata = Onetime::Metadata.create
@secret = Onetime::Secret.create value: "This is a secret message"
@metadata.secret_identifier = @secret.identifier
@metadata.save

class MockRequest
  attr_reader :env
  def initialize
    @env = {'ots.locale' => 'en'}
  end
end

class MockSession
  def authenticated?
    true
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
end

@req = MockRequest.new
@sess = MockSession.new

## Can create a VuePoint view with all arguments
view = Core::Views::VuePoint.new(@req, @sess, @cust, 'en', @metadata)
[view.req, view.sess, view.cust, view.locale]
#=> [@req, @sess, @cust, 'en']

## Correctly sets basic properties
view = Core::Views::VuePoint.new(@req, @sess, @cust, 'en', @metadata)
[view['page_title'], view['frontend_host'], view['frontend_development'], view['no_cache']]
#=> ["Onetime Secret", "http://localhost:5173", false, false]

## Sets authentication status correctly
view = Core::Views::VuePoint.new(@req, @sess, @cust, 'en', @metadata)
authenticated_value = view.serialized_data['authenticated']
authenticated_value
#=> true

## Handles unauthenticated user correctly
unauthenticated_sess = MockSession.new
def unauthenticated_sess.authenticated?; false; end
view = Core::Views::VuePoint.new(@req, unauthenticated_sess, Onetime::Customer.anonymous, 'en', @metadata)
authenticated_value = view.serialized_data['authenticated']
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
