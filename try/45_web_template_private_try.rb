# frozen_string_literal: true

# These tryouts test the Private view functionality in the OneTime application,
# with a focus on the initialization process and its arguments.
# They cover:
#
# 1. Creating and initializing a Private view with various arguments
# 2. Testing the visibility of different elements based on metadata state and user authentication
# 3. Verifying the correct generation of URIs and paths
# 4. Checking the handling of secret values and their display properties
#
# These tests ensure that the Private view correctly handles different scenarios
# and properly initializes based on the provided arguments.

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test.yaml')
OT.boot!

@email = 'tryouts+41@onetimesecret.com'
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

## Can create a Private view with all arguments
view = OT::App::Views::Private.new(@req, @sess, @cust, 'en', @metadata)
[view.req, view.sess, view.cust, view.locale]
#=> [@req, @sess, @cust, 'en']

## Correctly sets basic properties
view = OT::App::Views::Private.new(@req, @sess, @cust, 'en', @metadata)
[view[:title], view[:body_class], view[:metadata_key]]
#=> ["You saved a secret", :generate, @metadata.key]

## Sets authentication status correctly
view = OT::App::Views::Private.new(@req, @sess, @cust, 'en', @metadata)
view[:authenticated]
#=> true

## Handles unauthenticated user correctly
unauthenticated_sess = MockSession.new
def unauthenticated_sess.authenticated?; false; end
view = OT::App::Views::Private.new(@req, unauthenticated_sess, OT::Customer.anonymous, 'en', @metadata)
view[:authenticated]
#=> false

## Generates correct share URI
@this_view = OT::App::Views::Private.new(@req, @sess, @cust, 'en', @metadata)
@this_view.share_uri
#=> "#{@this_view.baseuri}/secret/#{@secret.key}"

## Sets locale correctly
view = OT::App::Views::Private.new(@req, @sess, @cust, 'es', @metadata)
view.locale
#=> 'es'

## Falls back to default locale if not provided
view = OT::App::Views::Private.new(@req, @sess, @cust, nil, @metadata)
view.locale
#=> 'en'

## Correctly sets expiration stamp
@metadata.ttl = 2.days
view = OT::App::Views::Private.new(@req, @sess, @cust, 'en', @metadata)
view[:expiration_stamp]
#=> "2 days"

## Shows secret link when appropriate
view = OT::App::Views::Private.new(@req, @sess, @cust, 'en', @metadata)
view[:show_secret_link]
#=> true

## Hides secret link when metadata is in received state
@metadata.received!
view = OT::App::Views::Private.new(@req, @sess, @cust, 'en', @metadata)
view[:show_secret_link]
#=> false

## Correctly determines if secret is a one-liner
view = OT::App::Views::Private.new(@req, @sess, @cust, 'en', @metadata)
view.one_liner
#=> true

## Correctly determines display lines for multi-line secrets
metadata = OT::Metadata.create
secret = OT::Secret.create value: "Line 1\nLine 2\nLine 3\nLine4\nLine5\nLine6"
metadata.secret_key = secret.key
metadata.save
view = OT::App::Views::Private.new(@req, @sess, @cust, 'en', metadata)
view.display_lines
#=> 7

# Teardown
@secret.destroy!
@metadata.destroy!
@cust.destroy!
