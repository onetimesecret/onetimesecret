require 'onetime'
require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

# Setup
OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

@canonical_domain = 'onetimesecret.com'
@parser = Onetime::DomainStrategy::Parser
@chooser = Onetime::DomainStrategy::Chooserator

# Basic Configuration Tests
## Config initialization with domains enabled
config = { domains: { enabled: true, default: @canonical_domain } }
Onetime::DomainStrategy.initialize_from_config(config)
Onetime::DomainStrategy.canonical_domain
#=> 'onetimesecret.com'

## Config initialization with domains disabled uses fallback host
config = { domains: { enabled: false }, host: 'fallback.com' }
Onetime::DomainStrategy.initialize_from_config(config)
Onetime::DomainStrategy.canonical_domain
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
#=> :canonical

## Detects subdomain strategy
@chooser.choose_strategy('sub.onetimesecret.com', @canonical_domain)
#=> :subdomain

## Detects custom domain strategy
@chooser.choose_strategy('customdomain.com', @canonical_domain)
#=> nil


# Teardown
Onetime::DomainStrategy.reset!
