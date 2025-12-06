# try/unit/helpers/homepage_mode/forwarded_headers_try.rb
#
# Tests for extract_forwarded_ips, extract_x_forwarded_for, and
# extract_rfc7239_forwarded methods in Onetime::Helpers::HomepageModeHelpers
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

  public :extract_forwarded_ips, :extract_x_forwarded_for, :extract_rfc7239_forwarded
end

## RFC 7239 Forwarded Header Extraction
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_FORWARDED' => 'for=192.0.2.43, for=198.51.100.17;by=203.0.113.43'
}
controller = TestHomepageController.new(env)
ips = controller.extract_rfc7239_forwarded
ips
#=> ['192.0.2.43', '198.51.100.17']

## RFC 7239 Forwarded Header - IPv6 with Brackets
env = {
  'REMOTE_ADDR' => '::1',
  'HTTP_FORWARDED' => 'for="[2001:db8::1]", for="[2001:db8::2]"'
}
controller = TestHomepageController.new(env)
ips = controller.extract_rfc7239_forwarded
ips
#=> ['2001:db8::1', '2001:db8::2']

## RFC 7239 Forwarded Header - Quoted Values
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_FORWARDED' => 'for="192.0.2.43", for="198.51.100.17"'
}
controller = TestHomepageController.new(env)
ips = controller.extract_rfc7239_forwarded
ips
#=> ['192.0.2.43', '198.51.100.17']

## Extract Forwarded IPs - X-Forwarded-For Type
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '192.0.2.43, 198.51.100.17'
}
controller = TestHomepageController.new(env)
ips = controller.extract_forwarded_ips('X-Forwarded-For')
ips
#=> ['192.0.2.43', '198.51.100.17']

## Extract Forwarded IPs - Forwarded Type
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_FORWARDED' => 'for=192.0.2.43, for=198.51.100.17'
}
controller = TestHomepageController.new(env)
ips = controller.extract_forwarded_ips('Forwarded')
ips
#=> ['192.0.2.43', '198.51.100.17']

## Extract Forwarded IPs - Both Type (Forwarded Present)
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_FORWARDED' => 'for=192.0.2.43',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.17'
}
controller = TestHomepageController.new(env)
ips = controller.extract_forwarded_ips('Both')
ips
#=> ['192.0.2.43']

## Extract Forwarded IPs - Both Type (Only X-Forwarded-For Present)
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.17'
}
controller = TestHomepageController.new(env)
ips = controller.extract_forwarded_ips('Both')
ips
#=> ['198.51.100.17']
