# try/unit/helpers/homepage_mode/client_ip_extraction_try.rb
#
# Tests for extract_client_ip_for_homepage and extract_ip_from_header methods
# in Onetime::Helpers::HomepageModeHelpers
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

  public :extract_client_ip_for_homepage, :extract_ip_from_header
end

## Extract Client IP - Uses REMOTE_ADDR by Default
env = { 'REMOTE_ADDR' => '10.0.1.100' }
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 0 })
ip
#=> '10.0.1.100'

## Extract Client IP - Ignores X-Forwarded-For when depth is 0
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 0 })
ip
#=> '10.0.1.100'

## Extract Client IP - Uses X-Forwarded-For with Depth 1
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1 })
ip
#=> '198.51.100.1'

## Extract Client IP - Uses X-Forwarded-For with Depth 2
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 203.0.113.5, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 2 })
ip
#=> '198.51.100.1'

## Extract Client IP - Single IP in X-Forwarded-For (Edge Case)
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1 })
ip
#=> '198.51.100.1'

## Extract Client IP - Using Forwarded Header
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_FORWARDED' => 'for=192.0.2.43, for=127.0.0.1'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1, 'trusted_ip_header' => 'Forwarded' })
ip
#=> '192.0.2.43'

## Extract Client IP - Using Both Headers (Forwarded Priority)
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_FORWARDED' => 'for=192.0.2.43, for=127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.17, 127.0.0.1'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1, 'trusted_ip_header' => 'Both' })
ip
#=> '192.0.2.43'

## Extract Client IP - Public IP from Header
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1 })
ip
#=> '203.0.113.1'

## Extract Client IP - Private IP from Header Falls Back to REMOTE_ADDR
# When extracted IP is private (proxy address), fall back to REMOTE_ADDR
# to get the actual client IP and prevent header spoofing attacks
env = {
  'REMOTE_ADDR' => '198.51.100.50',
  'HTTP_X_FORWARDED_FOR' => '10.0.1.100, 10.0.1.200'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1 })
ip
#=> '198.51.100.50'

## Extract Client IP - Depth 0 Ignores Headers
env = {
  'REMOTE_ADDR' => '203.0.113.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 0 })
ip
#=> '203.0.113.1'

## Extract IP From Header - X-Forwarded-For with Depth 1
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_ip_from_header('X-Forwarded-For', 1)
ip
#=> '198.51.100.1'

## Extract IP From Header - X-Forwarded-For with Depth 2
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 203.0.113.5, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_ip_from_header('X-Forwarded-For', 2)
ip
#=> '198.51.100.1'

## Extract IP From Header - Forwarded Header
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_FORWARDED' => 'for=192.0.2.43, for=127.0.0.1'
}
controller = TestHomepageController.new(env)
ip = controller.extract_ip_from_header('Forwarded', 1)
ip
#=> '192.0.2.43'

## Extract IP From Header - No Header Present
env = {
  'REMOTE_ADDR' => '10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_ip_from_header('X-Forwarded-For', 1)
ip
#=> nil
