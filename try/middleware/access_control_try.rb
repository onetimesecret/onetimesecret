#!/usr/bin/env ruby
# frozen_string_literal: true

# try/middleware/access_control_try.rb
#
# Tryouts for Onetime::Middleware::AccessControl
#
# Run: bundle exec try --agent try/middleware/access_control_try.rb

require 'rack'
require_relative '../../lib/onetime/middleware/access_control'

# Mock app that captures env for testing
@captured_env = nil
@mock_app = lambda do |env|
  @captured_env = env
  [200, { 'Content-Type' => 'text/plain' }, ['OK']]
end

# Helper to call middleware and return [status, captured_env]
def call_middleware(config, env = {})
  @captured_env = nil
  middleware = Onetime::Middleware::AccessControl.new(@mock_app, config)
  default_env = {
    'REMOTE_ADDR' => '203.0.113.1',
    'REQUEST_METHOD' => 'GET',
    'PATH_INFO' => '/',
  }
  status, _headers, _body = middleware.call(default_env.merge(env))
  [status, @captured_env]
end

## Middleware disabled - should passthrough without setting header

config = { enabled: false }
env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '10.0.0.1',
}

status, captured_env = call_middleware(config, env)
[status, captured_env.key?('HTTP_X_ACCESS_MODE')]
#=> [200, false]

## No trigger header - should passthrough without setting header

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = { 'REMOTE_ADDR' => '10.0.0.1' }

status, captured_env = call_middleware(config, env)
[status, captured_env.key?('HTTP_X_ACCESS_MODE')]
#=> [200, false]

## Trigger header present but secret mismatch - should passthrough

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'correct-secret' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'wrong-secret',
  'REMOTE_ADDR' => '10.0.0.1',
}

status, captured_env = call_middleware(config, env)
[status, captured_env.key?('HTTP_X_ACCESS_MODE')]
#=> [200, false]

## Trigger activated, IP in allowlist - should set allow mode

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8', '172.16.0.0/12'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '10.0.0.100',
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'normal']

## Trigger activated, IP NOT in allowlist - should set deny mode

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '203.0.113.1', # Public IP, not in allowlist
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'restricted']

## X-Forwarded-For takes precedence over REMOTE_ADDR

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'HTTP_X_FORWARDED_FOR' => '10.0.0.50, 192.168.1.1', # First IP is internal
  'REMOTE_ADDR' => '203.0.113.1', # External (ignored)
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'normal']

## Multiple CIDR blocks - match against any

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '172.20.5.10', # Matches second CIDR
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'normal']

## IPv6 address in allowlist

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['fc00::/7'], # IPv6 Unique Local Address
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => 'fc00::1', # Matches IPv6 ULA range
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'normal']

## IPv6 address NOT in allowlist

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['fc00::/7'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '2001:db8::1', # Public IPv6, not in allowlist
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'restricted']

## Custom header names

config = {
  enabled: true,
  trigger: { header: 'X-Custom-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'X-Custom-Mode', allow: 'allowed', deny: 'denied' },
}

env = {
  'HTTP_X_CUSTOM_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '10.0.0.1',
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_CUSTOM_MODE']]
#=> [200, 'allowed']

## Single IP address as /32 CIDR

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['203.0.113.5/32'], # Single IP
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '203.0.113.5', # Exact match
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'normal']

## Single IP mismatch

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['203.0.113.5/32'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '203.0.113.6', # Different IP
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'restricted']

## No client IP available - defaults to deny

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  # No REMOTE_ADDR or X-Forwarded-For
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'restricted']

## Empty allowed_cidrs - all IPs denied

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: [],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '10.0.0.1',
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'restricted']

## Trigger secret with special characters

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret!@#$%^&*()' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret!@#$%^&*()',
  'REMOTE_ADDR' => '10.0.0.1',
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_X_ACCESS_MODE']]
#=> [200, 'normal']

## Timing-safe secret comparison prevents timing attacks

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'a' * 32 },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

# Wrong secret with same length
env1 = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'b' * 32,
  'REMOTE_ADDR' => '10.0.0.1',
}

# Correct secret
env2 = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'a' * 32,
  'REMOTE_ADDR' => '10.0.0.1',
}

status1, captured_env1 = call_middleware(config, env1)
status2, captured_env2 = call_middleware(config, env2)

[captured_env1.key?('HTTP_X_ACCESS_MODE'), captured_env2['HTTP_X_ACCESS_MODE']]
#=> [false, 'normal']

## Always returns 200 - never blocks

config = {
  enabled: true,
  trigger: { header: 'X-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'X-Access-Mode', allow: 'normal', deny: 'restricted' },
}

# External IP that would be denied
env = {
  'HTTP_X_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '203.0.113.1',
}

# Middleware needs to return full response for this test
middleware = Onetime::Middleware::AccessControl.new(@mock_app, config)
default_env = {
  'REMOTE_ADDR' => '203.0.113.1',
  'REQUEST_METHOD' => 'GET',
  'PATH_INFO' => '/',
}
status, headers, body = middleware.call(default_env.merge(env))
[status, body.join]
#=> [200, 'OK']

## Configuration normalization - missing keys get defaults

config = {
  enabled: true,
  trigger: { secret: 'secret123' }, # Missing header
  allowed_cidrs: ['10.0.0.0/8'],
  # Missing mode config
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123', # Default header name
  'REMOTE_ADDR' => '10.0.0.1',
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']] # Default mode header name and value
#=> [200, 'normal']

## Validation error when enabled but no secret

begin
  config = {
    enabled: true,
    trigger: { secret: '' }, # Empty secret
    allowed_cidrs: ['10.0.0.0/8'],
  }

  Onetime::Middleware::AccessControl.new(@mock_app, config)
  'no error'
rescue ArgumentError => e
  e.message.include?('trigger.secret')
end
#=> true
