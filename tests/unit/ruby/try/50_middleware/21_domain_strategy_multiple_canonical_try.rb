require 'onetime'
require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

# Setup
OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

@canonical_domain = 'eu.onetimesecret.com'
@parser = Onetime::DomainStrategy::Parser
@chooser = Onetime::DomainStrategy::Chooserator

# Domain Validation Tests
## Valid canonical domain passes validation
@chooser.choose_strategy(@canonical_domain, @canonical_domain)
#=> :canonical

## Valid subdomain passes validation
@chooser.choose_strategy('onetimesecret.com', @canonical_domain)
#=> nil

## Domain with consecutive dots fails validation
@chooser.choose_strategy('us.onetimesecret.com', @canonical_domain)
#=> :canonical

## Valid subdomain passes validation
@chooser.choose_strategy('onetimesecret.com', 'onetimesecret.com')
#=> :canonical

## Valid subdomain passes validation
@chooser.choose_strategy('eu.onetimesecret.com', 'onetimesecret.com')
#=> :subdomain

## Valid subdomain passes validation
@chooser.choose_strategy('onetimesecret.com', 'eu.onetimesecret.com')
#=> nil
