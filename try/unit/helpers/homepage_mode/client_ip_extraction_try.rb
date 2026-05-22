# try/unit/helpers/homepage_mode/client_ip_extraction_try.rb
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

  public :extract_client_ip_for_homepage
end

# extract_client_ip_for_homepage delegates to Rack::Request#ip, which
# ConfigureTrustedProxy configures globally from site.network.trusted_proxy.
# Homepage mode no longer does its own proxy-depth extraction.

## Extract Client IP - Direct connection uses REMOTE_ADDR
env = { 'REMOTE_ADDR' => '203.0.113.10' }
controller = TestHomepageController.new(env)
controller.extract_client_ip_for_homepage
#=> '203.0.113.10'

## Extract Client IP - Behind a trusted (loopback) proxy uses X-Forwarded-For
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '203.0.113.10, 127.0.0.1'
}
controller = TestHomepageController.new(env)
controller.extract_client_ip_for_homepage
#=> '203.0.113.10'

## Extract Client IP - An untrusted peer cannot spoof via X-Forwarded-For
# When REMOTE_ADDR is a public address, Rack::Request#ip does not trust the
# forwarded chain, so the client-supplied header is ignored.
env = {
  'REMOTE_ADDR' => '203.0.113.10',
  'HTTP_X_FORWARDED_FOR' => '10.0.0.99'
}
controller = TestHomepageController.new(env)
controller.extract_client_ip_for_homepage
#=> '203.0.113.10'

## Extract Client IP - Matches Rack::Request#ip exactly
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.7, 127.0.0.1'
}
controller = TestHomepageController.new(env)
controller.extract_client_ip_for_homepage == controller.req.ip
#=> true
