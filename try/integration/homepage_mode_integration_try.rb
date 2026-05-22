# try/integration/homepage_mode_integration_try.rb
#
# frozen_string_literal: true

require_relative '../../lib/onetime'
require 'rack/mock'

OT.boot! :test

# Load the controller
require_relative '../../apps/web/core/controllers/base'

# Helper to create controller with stubbed config
def create_controller_with_config(env, homepage_config)
  # Create controller class that stubs OT.conf
  controller_class = Class.new do
    include Core::Controllers::Base
    attr_accessor :req, :res, :test_homepage_config

    def initialize(env = {}, homepage_config = {})
      @req = Rack::Request.new(env)
      @res = Rack::Response.new
      @test_homepage_config = homepage_config
    end

    public :determine_homepage_mode

    # Override the config access to use our test config
    def determine_homepage_mode
      ui_config = { 'homepage' => @test_homepage_config }
      homepage_config = ui_config['homepage'] || {}

      configured_mode = homepage_config['mode']
      return nil unless %w[internal external].include?(configured_mode)

      # Initialize CIDR matchers
      @cidr_matchers ||= compile_homepage_cidrs(homepage_config)

      # Extract client IP (resolved by Rack::Request#ip)
      client_ip = extract_client_ip_for_homepage
      mode_header_name = homepage_config['request_header']

      # Priority 1: Check CIDR match
      if client_ip && ip_matches_homepage_cidrs?(client_ip)
        return configured_mode
      end

      # Priority 2: Fallback to header check
      if mode_header_name && header_matches_mode?(mode_header_name, configured_mode)
        return configured_mode
      end

      nil
    end
  end

  controller_class.new(env, homepage_config)
end

## Integration: Internal mode with CIDR match
# Client IP is resolved by Rack::Request#ip, which walks X-Forwarded-For and
# skips the trusted (loopback) proxy hop.
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['198.51.100.0/24', '203.0.113.0/24'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.50, 127.0.0.1'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: External mode with CIDR match
config = {
  'mode' => 'external',
  'matching_cidrs' => ['203.0.113.0/24'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '203.0.113.50, 127.0.0.1'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'external'

## Integration: No CIDR match, header fallback to internal
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['10.0.0.0/8'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 127.0.0.1',
  'HTTP_O_HOMEPAGE_MODE' => 'internal'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: No CIDR match, header fallback to external
config = {
  'mode' => 'external',
  'matching_cidrs' => ['10.0.0.0/8'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 127.0.0.1',
  'HTTP_O_HOMEPAGE_MODE' => 'external'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'external'

## Integration: No CIDR match, wrong header value returns nil
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['10.0.0.0/8'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 127.0.0.1',
  'HTTP_O_HOMEPAGE_MODE' => 'wrong_value'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> nil

## Integration: No CIDR match, no header returns nil
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['10.0.0.0/8'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 127.0.0.1'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> nil

## Integration: CIDR takes priority over header
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['198.51.100.0/24'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.50, 127.0.0.1',
  'HTTP_O_HOMEPAGE_MODE' => 'external'  # Wrong value ignored when CIDR matches
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: Multiple CIDRs, matches second range
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['198.51.100.0/24', '203.0.113.0/24', '192.0.2.0/24'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '203.0.113.50, 127.0.0.1'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: Behind multiple proxies with private intermediate hops
# Rack::Request#ip skips RFC1918 / loopback hops, returning the public client.
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['198.51.100.0/24'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.50, 10.0.0.5, 127.0.0.1'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: Direct connection (no proxy) uses REMOTE_ADDR
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['198.51.100.0/24'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '198.51.100.10'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: Invalid mode returns nil
config = {
  'mode' => 'invalid_mode',
  'matching_cidrs' => ['10.0.0.0/8'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 127.0.0.1'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> nil

## Integration: Empty mode returns nil
config = {
  'mode' => '',
  'matching_cidrs' => ['10.0.0.0/8'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 127.0.0.1'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> nil

## Integration: No mode configured returns nil
config = {
  'matching_cidrs' => ['10.0.0.0/8'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 127.0.0.1'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> nil

## Integration: IPv6 CIDR match
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['2001:db8::/48'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '::1',
  'HTTP_X_FORWARDED_FOR' => '2001:db8::1, ::1'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: Mixed IPv4 and IPv6 CIDRs
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['198.51.100.0/24', '2001:db8::/48'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '::1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.50, ::1'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: CIDR with invalid prefix is rejected, falls back to header
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['192.168.1.1/32'],  # Too specific, will be rejected
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '192.168.1.1, 127.0.0.1',
  'HTTP_O_HOMEPAGE_MODE' => 'internal'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: Empty CIDR list, header only
config = {
  'mode' => 'internal',
  'matching_cidrs' => [],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.1, 127.0.0.1',
  'HTTP_O_HOMEPAGE_MODE' => 'internal'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: Custom header name
config = {
  'mode' => 'internal',
  'matching_cidrs' => [],
  'request_header' => 'X-Custom-Access'
}
env = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_X_CUSTOM_ACCESS' => 'internal'
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: Real-world scenario - Corporate network with public egress
config = {
  'mode' => 'internal',
  'matching_cidrs' => ['198.51.100.0/24'],
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '172.16.0.1',
  'HTTP_X_FORWARDED_FOR' => '198.51.100.50, 172.16.0.1'  # Corporate egress IP
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'internal'

## Integration: Real-world scenario - External user
config = {
  'mode' => 'external',
  'matching_cidrs' => ['0.0.0.0/0'],  # Match all IPs (public mode)
  'request_header' => 'O-Homepage-Mode'
}
env = {
  'REMOTE_ADDR' => '172.16.0.1',
  'HTTP_X_FORWARDED_FOR' => '93.184.216.34, 172.16.0.1'  # Public internet IP
}
controller = create_controller_with_config(env, config)
mode = controller.determine_homepage_mode
mode
#=> 'external'
