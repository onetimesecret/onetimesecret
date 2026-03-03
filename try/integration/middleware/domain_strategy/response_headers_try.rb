# try/integration/middleware/domain_strategy/response_headers_try.rb
#
# frozen_string_literal: true

# Tests for O-Domain-Strategy and O-Display-Domain response headers.
#
# These headers mirror the env['onetime.domain_strategy'] and
# env['onetime.display_domain'] values set during request processing,
# exposed as response headers for debugging and downstream consumers.

require_relative '../../../support/test_helpers'

require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

# Setup
OT.boot! :test, false

@strategy_class = Onetime::Middleware::DomainStrategy
@canonical_domain = 'onetimesecret.com'

# The test config has site.host = '127.0.0.1:3000' and domains disabled.
# When domains are disabled, the middleware falls back to site.host.
@fallback_host = OT.conf.dig('site', 'host')

def create_app
  ->(env) { [200, {}, ['OK']] }
end

def enable_runtime_domains!
  Onetime::Runtime.features = Onetime::Runtime.features.with(domains_enabled: true)
end

def disable_runtime_domains!
  Onetime::Runtime.features = Onetime::Runtime.features.with(domains_enabled: false)
end

# Fully enable domains: class-level config + runtime feature flag.
# This sets canonical_domain_parsed so Chooserator can classify domains.
def enable_domains_fully!
  config = { 'enabled' => true, 'default' => @canonical_domain }
  @strategy_class.initialize_from_config(config)
  enable_runtime_domains!
end

def enable_domains_and_context!
  enable_domains_fully!
  @strategy_class.class_eval { @domain_context_enabled = true }
end

def disable_domain_context!
  @strategy_class.class_eval { @domain_context_enabled = false }
end

# -- Canonical domain: headers when domains feature is disabled --

## O-Domain-Strategy header is "canonical" when domains feature is disabled
middleware = @strategy_class.new(create_app)
disable_runtime_domains!
env = { Rack::DetectHost.result_field_name => 'anything.example.org' }
status, headers, body = middleware.call(env)
headers['O-Domain-Strategy']
#=> 'canonical'

## O-Display-Domain header is the fallback site host when domains feature is disabled
middleware = @strategy_class.new(create_app)
disable_runtime_domains!
env = { Rack::DetectHost.result_field_name => 'anything.example.org' }
status, headers, body = middleware.call(env)
headers['O-Display-Domain']
#=> @fallback_host

## Both headers are strings when domains feature is disabled
middleware = @strategy_class.new(create_app)
disable_runtime_domains!
env = { Rack::DetectHost.result_field_name => 'anything.example.org' }
status, headers, body = middleware.call(env)
[headers['O-Domain-Strategy'].is_a?(String), headers['O-Display-Domain'].is_a?(String)]
#=> [true, true]

# -- Canonical domain: headers when domains enabled and host is canonical --

## O-Domain-Strategy header is "canonical" for the canonical domain
enable_domains_fully!
disable_domain_context!
middleware = @strategy_class.new(create_app)
env = { Rack::DetectHost.result_field_name => @canonical_domain }
status, headers, body = middleware.call(env)
headers['O-Domain-Strategy']
#=> 'canonical'

## O-Display-Domain header is the canonical domain for a canonical request
enable_domains_fully!
disable_domain_context!
middleware = @strategy_class.new(create_app)
env = { Rack::DetectHost.result_field_name => @canonical_domain }
status, headers, body = middleware.call(env)
headers['O-Display-Domain']
#=> @canonical_domain

# -- Subdomain: headers for subdomain of canonical --

## O-Domain-Strategy header is "subdomain" for a subdomain of the canonical domain
enable_domains_fully!
disable_domain_context!
middleware = @strategy_class.new(create_app)
env = { Rack::DetectHost.result_field_name => 'api.onetimesecret.com' }
status, headers, body = middleware.call(env)
headers['O-Domain-Strategy']
#=> 'subdomain'

## O-Display-Domain header is the subdomain for a subdomain request
enable_domains_fully!
disable_domain_context!
middleware = @strategy_class.new(create_app)
env = { Rack::DetectHost.result_field_name => 'api.onetimesecret.com' }
status, headers, body = middleware.call(env)
headers['O-Display-Domain']
#=> 'api.onetimesecret.com'

# -- Custom domain via override header --

## O-Domain-Strategy header is "custom" when domain context override is active
middleware = @strategy_class.new(create_app)
enable_domains_and_context!
env = {
  'HTTP_O_DOMAIN_CONTEXT' => 'partner.example.com',
  Rack::DetectHost.result_field_name => @canonical_domain,
}
status, headers, body = middleware.call(env)
headers['O-Domain-Strategy']
#=> 'custom'

## O-Display-Domain header is the override domain when domain context override is active
middleware = @strategy_class.new(create_app)
enable_domains_and_context!
env = {
  'HTTP_O_DOMAIN_CONTEXT' => 'partner.example.com',
  Rack::DetectHost.result_field_name => @canonical_domain,
}
status, headers, body = middleware.call(env)
headers['O-Display-Domain']
#=> 'partner.example.com'

# -- Invalid domain: nil strategy becomes :invalid --

## O-Domain-Strategy header is "invalid" when Chooserator returns nil
enable_domains_fully!
disable_domain_context!
middleware = @strategy_class.new(create_app)
env = { Rack::DetectHost.result_field_name => '.leading-dot.invalid' }
status, headers, body = middleware.call(env)
headers['O-Domain-Strategy']
#=> 'invalid'

# -- Header/env consistency --

## O-Domain-Strategy header matches env['onetime.domain_strategy'].to_s
enable_domains_fully!
disable_domain_context!
middleware = @strategy_class.new(create_app)
env = { Rack::DetectHost.result_field_name => @canonical_domain }
status, headers, body = middleware.call(env)
headers['O-Domain-Strategy'] == env['onetime.domain_strategy'].to_s
#=> true

## O-Display-Domain header matches env['onetime.display_domain'].to_s
enable_domains_fully!
disable_domain_context!
middleware = @strategy_class.new(create_app)
env = { Rack::DetectHost.result_field_name => @canonical_domain }
status, headers, body = middleware.call(env)
headers['O-Display-Domain'] == env['onetime.display_domain'].to_s
#=> true

## Header/env consistency holds for subdomain requests
enable_domains_fully!
disable_domain_context!
middleware = @strategy_class.new(create_app)
env = { Rack::DetectHost.result_field_name => 'eu.onetimesecret.com' }
status, headers, body = middleware.call(env)
[
  headers['O-Domain-Strategy'] == env['onetime.domain_strategy'].to_s,
  headers['O-Display-Domain'] == env['onetime.display_domain'].to_s,
]
#=> [true, true]

## Header/env consistency holds for custom domain override
middleware = @strategy_class.new(create_app)
enable_domains_and_context!
env = {
  'HTTP_O_DOMAIN_CONTEXT' => 'custom.partner.org',
  Rack::DetectHost.result_field_name => @canonical_domain,
}
status, headers, body = middleware.call(env)
[
  headers['O-Domain-Strategy'] == env['onetime.domain_strategy'].to_s,
  headers['O-Display-Domain'] == env['onetime.display_domain'].to_s,
]
#=> [true, true]

# -- www variant treated as canonical --

## O-Domain-Strategy header is "canonical" for www variant
enable_domains_fully!
disable_domain_context!
middleware = @strategy_class.new(create_app)
env = { Rack::DetectHost.result_field_name => 'www.onetimesecret.com' }
status, headers, body = middleware.call(env)
headers['O-Domain-Strategy']
#=> 'canonical'

## O-Display-Domain header is the www variant (not stripped to apex)
enable_domains_fully!
disable_domain_context!
middleware = @strategy_class.new(create_app)
env = { Rack::DetectHost.result_field_name => 'www.onetimesecret.com' }
status, headers, body = middleware.call(env)
headers['O-Display-Domain']
#=> 'www.onetimesecret.com'

# -- Response status is passed through --

## Middleware does not alter the status code from the inner app
middleware = @strategy_class.new(create_app)
disable_runtime_domains!
env = {}
status, headers, body = middleware.call(env)
status
#=> 200

# Teardown
@strategy_class.reset!
ENV.delete('DOMAIN_CONTEXT')
