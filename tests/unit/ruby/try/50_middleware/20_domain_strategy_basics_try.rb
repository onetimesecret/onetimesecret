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
Onetime::DomainStrategy.parse_config(config)
Onetime::DomainStrategy.canonical_domain
#=> 'onetimesecret.com'

## Config initialization with domains disabled uses fallback host
config = { domains: { enabled: false }, host: 'fallback.com' }
Onetime::DomainStrategy.parse_config(config)
Onetime::DomainStrategy.canonical_domain
#=> 'fallback.com'

# Domain Validation Tests
## Valid canonical domain passes validation
@parser.valid?(@canonical_domain)
#=> true

## Valid subdomain passes validation
@parser.valid?('api.onetimesecret.com')
#=> true

## Domain with consecutive dots fails validation
@parser.valid?('invalid..onetimesecret.com')
#=> false

## Domain with leading dot fails validation
@parser.valid?('.leading-dot.com')
#=> false

## Domain with trailing dot fails validation
@parser.valid?('trailing-dot.com.')
#=> false

# Domain Normalization Tests
## Normalizes canonical domain correctly
@parser.normalize(@canonical_domain)
#=> 'onetimesecret.com'

## Handles case-insensitive normalization
@parser.normalize('ONETIMESECRET.COM')
#=> 'onetimesecret.com'

## Preserves valid IDN domains
@parser.normalize('xn--mnchen-3ya.de')
#=> 'xn--mnchen-3ya.de'

## Strips whitespace during normalization
@parser.normalize('  onetimesecret.com  ')
#=> 'onetimesecret.com'

# Strategy Detection Tests
## Detects canonical domain strategy
@chooser.choose_strategy(@canonical_domain, @canonical_domain)
#=> :canonical

## Detects subdomain strategy
@chooser.choose_strategy('sub.onetimesecret.com', @canonical_domain)
#=> :subdomain

## Detects custom domain strategy
@chooser.choose_strategy('customdomain.com', @canonical_domain)
#=> :custom

# Domain Relationship Tests
## Validates peer domain relationship
@chooser.peer_of?('blog.example.com', 'shop.example.com')
#=> true

## Validates subdomain relationship
@chooser.subdomain_of?('api.example.com', 'example.com')
#=> true

## Validates case-insensitive domain equality
@chooser.equal_to?('Example.com', 'example.com')
#=> true

# Error Handling Tests
## Raises error for nil domain
begin
  @parser.normalize(nil)
rescue PublicSuffix::DomainInvalid => e
  e.class
end
#=> PublicSuffix::DomainInvalid

## Raises error for invalid characters
begin
  @parser.normalize('inv@lid.com')
rescue PublicSuffix::DomainInvalid => e
  e.class
end
#=> PublicSuffix::DomainInvalid

## Raises error for overlong domain labels
begin
  @parser.normalize("#{'a' * 64}.example.com")
rescue PublicSuffix::DomainInvalid => e
  e.class
end
#=> PublicSuffix::DomainInvalid

# Teardown
Onetime::DomainStrategy.reset! if Onetime::DomainStrategy.respond_to?(:reset!)
