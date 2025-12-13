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

# Helper to enable domain context at class level
def enable_domain_context!
  # Access the class singleton to set the class instance variable
  @strategy_class.class_eval { @domain_context_enabled = true }
end

# Helper to disable domain context at class level
def disable_domain_context!
  @strategy_class.class_eval { @domain_context_enabled = false }
end

# Helper to create middleware instance with domain context enabled
def create_middleware_with_override_enabled
  # Create middleware first (this triggers initialize_from_config internally)
  middleware = @strategy_class.new(create_app)

  # Then enable domain context AFTER middleware creation
  # (since the constructor calls initialize_from_config which would overwrite)
  enable_domain_context!

  middleware
end

# Helper to create middleware instance with domain context disabled
def create_middleware_with_override_disabled
  # Create middleware first
  middleware = @strategy_class.new(create_app)

  # Ensure domain context is disabled
  disable_domain_context!

  middleware
end

# Domain Context Override Detection Tests

## detect_domain_override returns nil when feature is disabled
middleware = create_middleware_with_override_disabled
env = {}
middleware.detect_domain_override(env)
#=> [nil, nil]

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

## detect_domain_override ignores empty header
middleware = create_middleware_with_override_enabled
env = { 'HTTP_O_DOMAIN_CONTEXT' => '' }
middleware.detect_domain_override(env)
#=> [nil, nil]

# Override Strategy Determination Tests

## determine_override_strategy returns :custom_simulated for non-existent domain
middleware = create_middleware_with_override_enabled
middleware.determine_override_strategy('nonexistent.acme.com')
#=> :custom_simulated

## determine_override_strategy returns :custom_simulated for fictional domain
middleware = create_middleware_with_override_enabled
middleware.determine_override_strategy('secrets.fictional-company.com')
#=> :custom_simulated

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

## call method uses override strategy for non-existent domain
middleware = create_middleware_with_override_enabled
env = {
  'HTTP_O_DOMAIN_CONTEXT' => 'fictional.acme.com',
  Rack::DetectHost.result_field_name => @canonical_domain,
}
middleware.call(env)
env['onetime.domain_strategy']
#=> :custom_simulated

## call method falls back to normal behavior when override disabled
middleware = create_middleware_with_override_disabled
env = {
  'HTTP_O_DOMAIN_CONTEXT' => 'override.example.com',
  Rack::DetectHost.result_field_name => @canonical_domain,
}
middleware.call(env)
# When override is disabled, falls back to normal behavior
# In test config, canonical domain is 127.0.0.1:3000 (from site.host)
env['onetime.display_domain']
#=> '127.0.0.1:3000'

## call method returns canonical when detected host matches canonical domain
middleware = create_middleware_with_override_enabled
# Use the actual canonical domain from config (127.0.0.1:3000 in test mode)
actual_canonical = middleware.canonical_domain
env = {
  Rack::DetectHost.result_field_name => actual_canonical,
}
middleware.call(env)
env['onetime.domain_strategy']
#=> :canonical

## call method uses implicit override when detected host differs from canonical
middleware = create_middleware_with_override_enabled
env = {
  Rack::DetectHost.result_field_name => 'custom.example.org',
}
middleware.call(env)
[env['onetime.display_domain'], env['onetime.domain_strategy']]
#=> ['custom.example.org', :custom_simulated]

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
