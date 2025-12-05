# try/unit/homepage_mode_try.rb
#
# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'test'
require_relative '../../lib/onetime'
require 'rack/mock'

OT.boot! :test

# Load the controller
require_relative '../../apps/web/core/controllers/base'

# Create a test controller class that includes the base controller methods
class TestHomepageController
  include Core::Controllers::Base

  attr_accessor :req, :res

  def initialize(env = {})
    @req = Rack::Request.new(env)
    @res = Rack::Response.new
  end

  # Make the private methods accessible for testing
  public :compile_homepage_cidrs, :validate_cidr_privacy,
         :extract_client_ip_for_homepage, :ip_matches_homepage_cidrs?, :header_matches_mode?,
         :extract_forwarded_ips, :extract_x_forwarded_for, :extract_rfc7239_forwarded,
         :extract_ip_from_header, :private_ip?
end

# Create a controller instance for testing
@controller = TestHomepageController.new({})

## IPv4 CIDR Compilation - Valid /24
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['192.168.1.0/24']
})
cidrs.length
#=> 1

## IPv4 CIDR Compilation - Valid /8
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['10.0.0.0/8']
})
cidrs.length
#=> 1

## IPv4 CIDR Privacy Validation - /25 is Rejected
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['192.168.1.0/25']
})
cidrs.length
#=> 0

## IPv4 CIDR Privacy Validation - /32 is Rejected
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['192.168.1.1/32']
})
cidrs.length
#=> 0

## IPv6 CIDR Privacy Validation - /48 is Valid
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['2001:db8::/48']
})
cidrs.length
#=> 1

## IPv6 CIDR Privacy Validation - /64 is Rejected
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['2001:db8::/64']
})
cidrs.length
#=> 0

## Invalid CIDR String Handling
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['invalid_cidr', '10.0.0.0/8']
})
cidrs.length
#=> 1

## Empty CIDR List
cidrs = @controller.compile_homepage_cidrs({
  'matching_cidrs' => []
})
cidrs.length
#=> 0

## IP Matching - IPv4 Match
@controller.instance_variable_set(:@cidr_matchers, @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['10.0.0.0/8']
}))
@controller.ip_matches_homepage_cidrs?('10.0.1.100')
#=> true

## IP Matching - IPv4 No Match
@controller.instance_variable_set(:@cidr_matchers, @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['10.0.0.0/8']
}))
@controller.ip_matches_homepage_cidrs?('192.168.1.1')
#=> false

## IP Matching - Multiple CIDRs
@controller.instance_variable_set(:@cidr_matchers, @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['10.0.0.0/8', '192.168.0.0/16', '172.16.0.0/12']
}))
@controller.ip_matches_homepage_cidrs?('192.168.1.100')
#=> true

## IP Matching - Empty IP
@controller.instance_variable_set(:@cidr_matchers, @controller.compile_homepage_cidrs({
  'matching_cidrs' => ['10.0.0.0/8']
}))
@controller.ip_matches_homepage_cidrs?('')
#=> false

## IP Matching - Empty Matchers
@controller.instance_variable_set(:@cidr_matchers, [])
@controller.ip_matches_homepage_cidrs?('10.0.1.100')
#=> false

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
# X-Forwarded-For: client_ip, proxy_ip
# Remove last 1 (proxy_ip), return client_ip
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1 })
ip
#=> '198.51.100.1'

## Extract Client IP - Uses X-Forwarded-For with Depth 2
# X-Forwarded-For: client_ip, proxy1_ip, proxy2_ip
# Remove last 2 (proxy1, proxy2), return client_ip
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 203.0.113.5, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 2 })
ip
#=> '198.51.100.1'

## Extract Client IP - Single IP in X-Forwarded-For (Edge Case)
# Only 1 IP but depth=1, should return that IP (client sent directly to proxy)
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1 })
ip
#=> '198.51.100.1'

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

## Client IP Extraction - Using Forwarded Header
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_FORWARDED' => 'for=192.0.2.43, for=127.0.0.1'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1, 'trusted_ip_header' => 'Forwarded' })
ip
#=> '192.0.2.43'

## Client IP Extraction - Using Both Headers (Forwarded Priority)
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_FORWARDED' => 'for=192.0.2.43, for=127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.17, 127.0.0.1'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1, 'trusted_ip_header' => 'Both' })
ip
#=> '192.0.2.43'

## Private IP Detection - IPv4 Private (10.0.0.0/8)
controller = TestHomepageController.new({})
controller.private_ip?('10.0.1.100')
#=> true

## Private IP Detection - IPv4 Private (172.16.0.0/12)
controller = TestHomepageController.new({})
controller.private_ip?('172.16.5.1')
#=> true

## Private IP Detection - IPv4 Private (192.168.0.0/16)
controller = TestHomepageController.new({})
controller.private_ip?('192.168.1.1')
#=> true

## Private IP Detection - IPv4 Loopback
controller = TestHomepageController.new({})
controller.private_ip?('127.0.0.1')
#=> true

## Private IP Detection - IPv4 Link-Local
controller = TestHomepageController.new({})
controller.private_ip?('169.254.1.1')
#=> true

## Private IP Detection - IPv4 Public
controller = TestHomepageController.new({})
controller.private_ip?('203.0.113.1')
#=> false

## Private IP Detection - IPv6 Loopback
controller = TestHomepageController.new({})
controller.private_ip?('::1')
#=> true

## Private IP Detection - IPv6 Unique Local
controller = TestHomepageController.new({})
controller.private_ip?('fc00::1')
#=> true

## Private IP Detection - IPv6 Link-Local
controller = TestHomepageController.new({})
controller.private_ip?('fe80::1')
#=> true

## Private IP Detection - IPv6 Public
controller = TestHomepageController.new({})
controller.private_ip?('2001:db8::1')
#=> false

## Private IP Detection - Empty String
controller = TestHomepageController.new({})
controller.private_ip?('')
#=> true

## Private IP Detection - Nil
controller = TestHomepageController.new({})
controller.private_ip?(nil)
#=> true

## Private IP Detection - Invalid IP
controller = TestHomepageController.new({})
controller.private_ip?('not_an_ip')
#=> true

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

## Client IP Extraction - Public IP from Header
env = {
  'REMOTE_ADDR' => '10.0.1.100',
  'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1 })
ip
#=> '203.0.113.1'

## Client IP Extraction - Private IP from Header Falls Back to REMOTE_ADDR
env = {
  'REMOTE_ADDR' => '198.51.100.50',
  'HTTP_X_FORWARDED_FOR' => '10.0.1.100, 10.0.1.200'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 1 })
ip
#=> '198.51.100.50'

## Client IP Extraction - Depth 0 Ignores Headers
env = {
  'REMOTE_ADDR' => '203.0.113.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 10.0.1.100'
}
controller = TestHomepageController.new(env)
ip = controller.extract_client_ip_for_homepage({ 'trusted_proxy_depth' => 0 })
ip
#=> '203.0.113.1'
