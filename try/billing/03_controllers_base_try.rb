require_relative '../support/test_helpers'

# Billing Controllers Base tests
#
# Tests base controller functionality for billing controllers.

## Setup: Load billing base controller
require 'apps/web/billing/controllers/base'

## Create mock request and response
@req = Rack::Request.new({
  'REQUEST_METHOD' => 'GET',
  'PATH_INFO' => '/billing/org/test123',
  'rack.input' => StringIO.new,
  'HTTP_ACCEPT' => 'application/json',
  'rack.locale' => ['en']
})
@res = Rack::Response.new

## Create controller instance
@controller = Class.new do
  include Billing::Controllers::Base
end.new(@req, @res)
@controller.class.ancestors.include?(Billing::Controllers::Base)
#=> true

## Verify request accessor
@controller.req.class
#=> Rack::Request

## Verify response accessor
@controller.res.class
#=> Rack::Response

## Verify locale accessor
@controller.locale
#=> nil

## Test JSON response helper
@data = @controller.json_response({ test: 'data' }, status: 200)
@data
#=> {:test=>"data"}

## Verify status was set
@controller.res.status
#=> 200

## Test JSON success helper
@success = @controller.json_success('Operation successful')
@success
#=> {:success=>"Operation successful"}

## Test JSON error helper
@error = @controller.json_error('Something went wrong', status: 400)
@error
#=> {:error=>"Something went wrong"}

## Test JSON error with field error
@error_with_field = @controller.json_error('Invalid email', field_error: ['email', 'invalid'], status: 400)
@error_with_field[:error]
#=> 'Invalid email'

## Verify field error included
@error_with_field['field-error']
#=> ['email', 'invalid']

## Test json_requested? helper (protected method)
@controller.send(:json_requested?)
#=> true

## Create HTML request
@html_req = Rack::Request.new({
  'REQUEST_METHOD' => 'GET',
  'PATH_INFO' => '/billing/org/test123',
  'rack.input' => StringIO.new,
  'HTTP_ACCEPT' => 'text/html',
  'rack.locale' => ['en']
})
@html_controller = Class.new do
  include Billing::Controllers::Base
end.new(@html_req, Rack::Response.new)
@html_controller.send(:json_requested?)
#=> false
