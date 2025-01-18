require 'onetime'
require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

# Setup
OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

@canonical_domain = 'eu.example.com'
@parser = Onetime::DomainStrategy::Parser
@chooser = Onetime::DomainStrategy::Chooserator

# Domain Validation Tests
## Valid canonical domain passes validation
@chooser.choose_strategy(@canonical_domain, @canonical_domain)
#=> :canonical

## Valid subdomain passes validation
@chooser.choose_strategy('example.com', @canonical_domain)
#=> :canonical

## Domain with consecutive dots fails validation
@chooser.choose_strategy('us.example.com', @canonical_domain)
#=> :canonical

## Valid subdomain passes validation
@chooser.choose_strategy('example.com', 'example.com')
#=> :canonical

## Valid subdomain passes validation
@chooser.choose_strategy('eu.example.com', 'example.com')
#=> :subdomain

## Valid subdomain passes validation
@chooser.choose_strategy('example.com', 'eu.example.com')
#=> :canonical
