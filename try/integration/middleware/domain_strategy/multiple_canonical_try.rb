# try/50_middleware/21_domain_strategy_multiple_canonical_try.rb
#
# frozen_string_literal: true

require_relative '../../../support/test_helpers'

require 'middleware/detect_host'
require 'onetime/middleware/domain_strategy'

# Setup
OT.boot! :test, false

@canonical_domain = 'eu.example.com'
@parser = Onetime::Middleware::DomainStrategy::Parser
@chooser = Onetime::Middleware::DomainStrategy::Chooserator

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
