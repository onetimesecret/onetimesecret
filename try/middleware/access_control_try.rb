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
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '10.0.0.1',
}

status, captured_env = call_middleware(config, env)
[status, captured_env.key?('HTTP_O_ACCESS_MODE')]
#=> [200, false]

## No trigger header - should passthrough without setting header

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = { 'REMOTE_ADDR' => '10.0.0.1' }

status, captured_env = call_middleware(config, env)
[status, captured_env.key?('HTTP_O_ACCESS_MODE')]
#=> [200, false]

## Trigger header present but secret mismatch - should passthrough

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'correct-secret' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'wrong-secret',
  'REMOTE_ADDR' => '10.0.0.1',
}

status, captured_env = call_middleware(config, env)
[status, captured_env.key?('HTTP_O_ACCESS_MODE')]
#=> [200, false]

## Trigger activated, IP in allowlist - should set allow mode

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8', '172.16.0.0/12'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '10.0.0.100',
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'normal']

## Trigger activated, IP NOT in allowlist - should set deny mode

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '203.0.113.1', # Public IP, not in allowlist
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'protected']

## Default (trusted_proxy_depth=0): Uses REMOTE_ADDR, ignores X-Forwarded-For

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
  # trusted_proxy_depth defaults to 0
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'HTTP_X_FORWARDED_FOR' => '10.0.0.50, 192.168.1.1', # Ignored when depth=0
  'REMOTE_ADDR' => '203.0.113.1', # External - this is used
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'protected']

## Multiple CIDR blocks - match against any

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '172.20.5.10', # Matches second CIDR
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'normal']

## IPv6 address in allowlist

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['fc00::/7'], # IPv6 Unique Local Address
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => 'fc00::1', # Matches IPv6 ULA range
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'normal']

## IPv6 address NOT in allowlist

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['fc00::/7'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '2001:db8::1', # Public IPv6, not in allowlist
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'protected']

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
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['203.0.113.5/32'], # Single IP
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '203.0.113.5', # Exact match
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'normal']

## Single IP mismatch

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['203.0.113.5/32'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '203.0.113.6', # Different IP
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'protected']

## No client IP available - defaults to deny

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  # No REMOTE_ADDR or X-Forwarded-For
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'protected']

## Empty allowed_cidrs - all IPs denied

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: [],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'REMOTE_ADDR' => '10.0.0.1',
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'protected']

## Trigger secret with special characters

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret!@#$%^&*()' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret!@#$%^&*()',
  'REMOTE_ADDR' => '10.0.0.1',
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'normal']

## Timing-safe secret comparison prevents timing attacks

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'a' * 32 },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

# Wrong secret with same length
env1 = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'b' * 32,
  'REMOTE_ADDR' => '10.0.0.1',
}

# Correct secret
env2 = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'a' * 32,
  'REMOTE_ADDR' => '10.0.0.1',
}

status1, captured_env1 = call_middleware(config, env1)
status2, captured_env2 = call_middleware(config, env2)

[captured_env1.key?('HTTP_O_ACCESS_MODE'), captured_env2['HTTP_O_ACCESS_MODE']]
#=> [false, 'normal']

## Always returns 200 - never blocks

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
}

# External IP that would be denied
env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
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

## Trusted proxy depth = 0 (default): Ignores X-Forwarded-For

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
  trusted_proxy_depth: 0, # Default - ignore X-Forwarded-For
}

# Attacker tries to spoof internal IP via X-Forwarded-For
env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'HTTP_X_FORWARDED_FOR' => '10.0.0.1, 203.0.113.50', # Spoofed internal IP
  'REMOTE_ADDR' => '203.0.113.50', # Real external IP
}

status, captured_env = call_middleware(config, env)
# Should use REMOTE_ADDR (external IP), ignoring spoofed X-Forwarded-For
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'protected']

## Trusted proxy depth = 1: Uses rightmost IP from X-Forwarded-For

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
  trusted_proxy_depth: 1, # Trust 1 proxy
}

# Legitimate request through one proxy
env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'HTTP_X_FORWARDED_FOR' => '10.0.0.1, 10.0.1.100', # Client IP, Proxy IP
  'REMOTE_ADDR' => '10.0.1.100', # Proxy IP
}

status, captured_env = call_middleware(config, env)
# Should use client IP (rightmost before proxy)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'normal']

## Trusted proxy depth = 1: External IP is correctly denied

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
  trusted_proxy_depth: 1,
}

# External IP through proxy
env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 10.0.1.100', # External client, Proxy
  'REMOTE_ADDR' => '10.0.1.100',
}

status, captured_env = call_middleware(config, env)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'protected']

## Trusted proxy depth = 2: Handles two proxies

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
  trusted_proxy_depth: 2, # Trust 2 proxies
}

# Request through CDN and load balancer
env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'HTTP_X_FORWARDED_FOR' => '10.0.0.5, 10.0.1.100, 10.0.1.200', # Client, LB, CDN
  'REMOTE_ADDR' => '10.0.1.200', # CDN IP
}

status, captured_env = call_middleware(config, env)
# Should use client IP (3rd from right)
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'normal']

## Trusted proxy depth with short X-Forwarded-For chain

config = {
  enabled: true,
  trigger: { header: 'O-Access-Control-Trigger', secret: 'secret123' },
  allowed_cidrs: ['10.0.0.0/8'],
  mode: { header: 'O-Access-Mode', allow: 'normal', deny: 'protected' },
  trusted_proxy_depth: 2, # Expects 2 proxies
}

# But only 1 IP in chain (fallback to first)
env = {
  'HTTP_O_ACCESS_CONTROL_TRIGGER' => 'secret123',
  'HTTP_X_FORWARDED_FOR' => '10.0.0.5', # Only client IP
  'REMOTE_ADDR' => '10.0.1.100',
}

status, captured_env = call_middleware(config, env)
# Falls back to first (and only) IP
[status, captured_env['HTTP_O_ACCESS_MODE']]
#=> [200, 'normal']
