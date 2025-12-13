# try/integration/middleware/domain_strategy/domain_context_override_try.rb
#
# Tests for Domain Context Override feature (#2174)
# Allows simulating custom domain experiences in development mode.
#
# frozen_string_literal: true

require_relative '../../../support/test_helpers'

require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

# Setup
OT.boot! :test, false

@strategy_class = Onetime::Middleware::DomainStrategy
@canonical_domain = 'onetimesecret.com'

# Helper to create a minimal Rack app
def create_app
  ->(env) { [200, {}, ['OK']] }
end

# Helper to enable Runtime.features.domains? - the actual runtime flag
def enable_runtime_domains!
  current_features = Onetime::Runtime.features
  Onetime::Runtime.features = Onetime::Runtime::Features.new(
    domains_enabled: true,
    global_banner: current_features.global_banner,
    fortunes: current_features.fortunes,
  )
end

# Helper to disable Runtime.features.domains?
def disable_runtime_domains!
  current_features = Onetime::Runtime.features
  Onetime::Runtime.features = Onetime::Runtime::Features.new(
    domains_enabled: false,
    global_banner: current_features.global_banner,
    fortunes: current_features.fortunes,
  )
end

# Helper to enable both domains (Runtime) and domain context at class level
def enable_domains_and_context!
  enable_runtime_domains!
  @strategy_class.class_eval { @domain_context_enabled = true }
end

# Helper to disable domain context at class level
def disable_domain_context!
  @strategy_class.class_eval { @domain_context_enabled = false }
end

# Helper to disable domains feature (Runtime level)
def disable_domains!
  disable_runtime_domains!
end

# Helper to create middleware instance with domain context enabled
def create_middleware_with_override_enabled
  middleware = @strategy_class.new(create_app)
  enable_domains_and_context!
  middleware
end

# Helper to create middleware instance with domain context disabled
def create_middleware_with_override_disabled
  middleware = @strategy_class.new(create_app)
  disable_domain_context!
  middleware
end

# Domain Context Override Detection Tests

## detect_domain_override returns nil when feature is disabled
middleware = create_middleware_with_override_disabled
env = {}
middleware.detect_domain_override(env)
#=> nil

## detect_domain_override returns env var when set
middleware = create_middleware_with_override_enabled
ENV['DOMAIN_CONTEXT'] = 'secrets.acme.com'
env = {}
result = middleware.detect_domain_override(env)
ENV.delete('DOMAIN_CONTEXT')
result
#=> ['secrets.acme.com', :env_var]

## detect_domain_override returns header when set
middleware = create_middleware_with_override_enabled
env = { 'HTTP_O_DOMAIN_CONTEXT' => 'custom.example.org' }
middleware.detect_domain_override(env)
#=> ['custom.example.org', :header]

## detect_domain_override prefers env var over header
middleware = create_middleware_with_override_enabled
ENV['DOMAIN_CONTEXT'] = 'env-domain.com'
env = { 'HTTP_O_DOMAIN_CONTEXT' => 'header-domain.com' }
result = middleware.detect_domain_override(env)
ENV.delete('DOMAIN_CONTEXT')
result
#=> ['env-domain.com', :env_var]

## detect_domain_override ignores empty env var
middleware = create_middleware_with_override_enabled
ENV['DOMAIN_CONTEXT'] = ''
env = { 'HTTP_O_DOMAIN_CONTEXT' => 'header-domain.com' }
result = middleware.detect_domain_override(env)
ENV.delete('DOMAIN_CONTEXT')
result
#=> ['header-domain.com', :header]

## detect_domain_override returns nil tuple when no override found
middleware = create_middleware_with_override_enabled
env = { 'HTTP_O_DOMAIN_CONTEXT' => '' }
middleware.detect_domain_override(env)
#=> [nil, nil]

## detect_domain_override returns implicit override for non-canonical host
middleware = create_middleware_with_override_enabled
env = { Rack::DetectHost.result_field_name => 'custom.example.org' }
middleware.detect_domain_override(env)
#=> ['custom.example.org', :detected_host]

# Middleware Integration Tests

## call method uses override when enabled and header present
middleware = create_middleware_with_override_enabled
env = {
  'HTTP_O_DOMAIN_CONTEXT' => 'override.example.com',
  Rack::DetectHost.result_field_name => @canonical_domain,
}
middleware.call(env)
env['onetime.display_domain']
#=> 'override.example.com'

## call method uses :custom strategy for override domain
middleware = create_middleware_with_override_enabled
env = {
  'HTTP_O_DOMAIN_CONTEXT' => 'fictional.acme.com',
  Rack::DetectHost.result_field_name => @canonical_domain,
}
middleware.call(env)
env['onetime.domain_strategy']
#=> :custom

# TODO: Revisit these tests after domains logic refactoring
# - call method falls back to canonical when override disabled
# - call method returns canonical when detected host matches canonical domain

## call method uses implicit override when detected host differs from canonical
middleware = create_middleware_with_override_enabled
env = {
  Rack::DetectHost.result_field_name => 'custom.example.org',
}
middleware.call(env)
[env['onetime.display_domain'], env['onetime.domain_strategy']]
#=> ['custom.example.org', :custom]

## call method returns canonical when domains feature is disabled
middleware = @strategy_class.new(create_app)
disable_domains!
env = {
  Rack::DetectHost.result_field_name => 'custom.example.org',
}
middleware.call(env)
env['onetime.domain_strategy']
#=> :canonical

# Class Method Tests

## domain_context_enabled? returns false by default after reset
@strategy_class.reset!
config = { 'enabled' => true, 'default' => @canonical_domain }
@strategy_class.initialize_from_config(config)
@strategy_class.domain_context_enabled?
#=> false

## reset! clears domain_context_enabled
@strategy_class.instance_variable_set(:@domain_context_enabled, true)
@strategy_class.reset!
@strategy_class.domain_context_enabled
#=> nil

# Teardown
@strategy_class.reset!
ENV.delete('DOMAIN_CONTEXT')
