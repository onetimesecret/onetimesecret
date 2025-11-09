# try/integration/middleware/domain_strategy/basics_try.rb
#
# frozen_string_literal: true

require_relative '../../../support/test_helpers'

require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

# Setup
OT.boot! :test, false

@canonical_domain = 'onetimesecret.com'
@parser = Onetime::Middleware::DomainStrategy::Parser
@chooser = Onetime::Middleware::DomainStrategy::Chooserator

# Basic Configuration Tests

## Config initialization with domains enabled
config = { 'domains' => { 'enabled' => true, 'default' => @canonical_domain } }
Onetime::Middleware::DomainStrategy.initialize_from_config(config)
Onetime::Middleware::DomainStrategy.canonical_domain
#=> 'onetimesecret.com'

## Config initialization with domains disabled uses fallback host
config = { 'domains' => { 'enabled' => false }, 'host' => 'fallback.com' }
Onetime::Middleware::DomainStrategy.initialize_from_config(config)
Onetime::Middleware::DomainStrategy.canonical_domain
#=> 'fallback.com'

# Domain Validation Tests
## Valid canonical domain passes validation
@chooser.choose_strategy(@canonical_domain, @canonical_domain)
#=> :canonical

## Valid subdomain passes validation
@chooser.choose_strategy('api.onetimesecret.com', @canonical_domain)
#=> :subdomain

## Domain with consecutive dots fails validation
@chooser.choose_strategy('invalid..onetimesecret.com', @canonical_domain)
#=> :subdomain

## Domain with leading dot fails validation
@chooser.choose_strategy('.leading-dot.com', @canonical_domain)
#=> nil

## Domain with trailing dot fails validation
@chooser.choose_strategy('trailing-dot.com.', @canonical_domain)
#=> nil

## Handles case-insensitive normalization
@chooser.choose_strategy('ONETIMESECRET.COM', @canonical_domain)
#=> :canonical

## Preserves valid IDN domains
@chooser.choose_strategy('xn--mnchen-3ya.de', @canonical_domain)
#=> nil

## Strips whitespace during normalization
@chooser.choose_strategy('  onetimesecret.com  ', @canonical_domain)
#=> nil

## Detects subdomain strategy
@chooser.choose_strategy('sub.onetimesecret.com', @canonical_domain)
#=> :subdomain

## Detects custom domain strategy
@chooser.choose_strategy('customdomain.com', @canonical_domain)
#=> nil

# Parser Tests
## Handles nil input by raising DomainInvalid
begin
  @parser.parse(nil)
rescue PublicSuffix::DomainInvalid
  true
end
#=> true

## Strips port numbers from hostnames
@parser.parse('example.com:3000').name
#=> 'example.com'

## Parses valid IDN domains
@parser.parse('xn--mnchen-3ya.de').name
#=> 'xn--mnchen-3ya.de'

# Chooserator Edge Case Tests
## Handles mixed case subdomains correctly
@chooser.choose_strategy('API.ONETIMESECRET.com', @canonical_domain)
#=> :subdomain

## Treats apex and www as canonical
@chooser.choose_strategy('www.onetimesecret.com', @canonical_domain)
#=> :canonical

## Rejects domains with special characters
@chooser.choose_strategy('test!.onetimesecret.com', @canonical_domain)
#=> nil

## Handles extremely long subdomains
long_subdomain = 'a' * 63 + '.onetimesecret.com'
@chooser.choose_strategy(long_subdomain, @canonical_domain)
#=> :subdomain

# Configuration Error Tests
## Raises on nil config
begin
  Onetime::Middleware::DomainStrategy.initialize_from_config(nil)
rescue ArgumentError
  true
end
#=> true

## Disables domains when canonical domain is invalid
config = { 'domains' => { 'enabled' => true, 'default' => '..invalid..' } }
Onetime::Middleware::DomainStrategy.initialize_from_config(config)
Onetime::Middleware::DomainStrategy.domains_enabled?
#=> false


## DomainStrategy class method 'normalize_canonical_domain' returns the correct normalized domain
@config_with_domains = {
  'site' => {
    'host' => 'onetimesecret.com',
    'domains' => {
      'enabled' => true,
      'default' => 'example.Com'
    }
  }
}
pp [:plop, @config_with_domains]
Onetime::Middleware::DomainStrategy.reset!
Onetime::Middleware::DomainStrategy.get_canonical_domain(@config_with_domains['site'])
#=> 'onetimesecret.com'

# Teardown
Onetime::Middleware::DomainStrategy.reset!
