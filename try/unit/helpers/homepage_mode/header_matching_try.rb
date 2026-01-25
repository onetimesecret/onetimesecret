# try/unit/helpers/homepage_mode/header_matching_try.rb
#
# frozen_string_literal: true

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'rack/mock'
require_relative '../../../../apps/web/core/controllers/base'

class TestHomepageController
  include Core::Controllers::Base

  attr_accessor :req, :res

  def initialize(env = {})
    @req = Rack::Request.new(env)
    @res = Rack::Response.new
  end

  public :header_matches_mode?
end

## Header Check - Matches Internal Mode
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_O_HOMEPAGE_MODE' => 'internal'
}
controller = TestHomepageController.new(env)
result = controller.header_matches_mode?('O-Homepage-Mode', 'internal')
result
#=> true

## Header Check - Matches External Mode
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_O_HOMEPAGE_MODE' => 'external'
}
controller = TestHomepageController.new(env)
result = controller.header_matches_mode?('O-Homepage-Mode', 'external')
result
#=> true

## Header Check - Does Not Match Wrong Value
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_O_HOMEPAGE_MODE' => 'wrong_value'
}
controller = TestHomepageController.new(env)
result = controller.header_matches_mode?('O-Homepage-Mode', 'internal')
result
#=> false

## Header Check - Missing Header
env = {
  'REMOTE_ADDR' => '10.0.1.100'
}
controller = TestHomepageController.new(env)
result = controller.header_matches_mode?('O-Homepage-Mode', 'internal')
result
#=> false

## Header Check - Empty Header Value
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_O_HOMEPAGE_MODE' => ''
}
controller = TestHomepageController.new(env)
result = controller.header_matches_mode?('O-Homepage-Mode', 'internal')
result
#=> false

## Header Check - No Request Header Configured (nil header name)
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_O_HOMEPAGE_MODE' => 'internal'
}
controller = TestHomepageController.new(env)
result = controller.header_matches_mode?(nil, 'internal')
result
#=> false

## Header Check - Custom Header Name (with dashes)
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_CUSTOM_HEADER' => 'internal'
}
controller = TestHomepageController.new(env)
result = controller.header_matches_mode?('X-Custom-Header', 'internal')
result
#=> true

## Header Check - Empty header name
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_O_HOMEPAGE_MODE' => 'internal'
}
controller = TestHomepageController.new(env)
result = controller.header_matches_mode?('', 'internal')
result
#=> false
