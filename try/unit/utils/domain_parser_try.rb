# try/unit/utils/domain_parser_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Utils::DomainParser
#
# This module provides centralized hostname parsing and comparison utilities
# that properly respect domain boundaries using the PublicSuffix gem.
#
# The key security feature is preventing loose hostname matching that could
# allow attacker-controlled domains to pass validation. For example:
#   - `attacker-example.com` should NOT match `example.com`
#   - `example.com.attacker.com` should NOT match `example.com`
#
# Test categories:
#   1. extract_hostname - URI/string to normalized hostname
#   2. hostname_matches? - Exact hostname comparison
#   3. hostname_within_domain? - Subdomain checking via PublicSuffix
#   4. basically_valid? - Format validation

require_relative '../../support/test_helpers'

OT.boot! :test, false

## =================================================================
## extract_hostname - Basic extraction
## =================================================================

## Extract hostname from plain hostname
Onetime::Utils::DomainParser.extract_hostname('example.com')
#=> 'example.com'

## Extract hostname normalizes to lowercase
Onetime::Utils::DomainParser.extract_hostname('EXAMPLE.COM')
#=> 'example.com'

## Extract hostname strips port
Onetime::Utils::DomainParser.extract_hostname('example.com:443')
#=> 'example.com'

## Extract hostname strips port (high port)
Onetime::Utils::DomainParser.extract_hostname('example.com:8080')
#=> 'example.com'

## Extract hostname from https URL
Onetime::Utils::DomainParser.extract_hostname('https://example.com/path')
#=> 'example.com'

## Extract hostname from https URL with port
Onetime::Utils::DomainParser.extract_hostname('https://example.com:443/path')
#=> 'example.com'

## Extract hostname from http URL
Onetime::Utils::DomainParser.extract_hostname('http://sub.example.com/foo?bar=1')
#=> 'sub.example.com'

## Extract hostname from URI object
Onetime::Utils::DomainParser.extract_hostname(URI('https://foo.bar.com'))
#=> 'foo.bar.com'

## Extract hostname returns nil for nil input
Onetime::Utils::DomainParser.extract_hostname(nil)
#=> nil

## Extract hostname returns nil for empty string
Onetime::Utils::DomainParser.extract_hostname('')
#=> nil

## Extract hostname returns nil for whitespace only
Onetime::Utils::DomainParser.extract_hostname('   ')
#=> nil

## =================================================================
## hostname_matches? - Exact comparison (SECURITY CRITICAL)
## =================================================================

## Exact match returns true
Onetime::Utils::DomainParser.hostname_matches?('example.com', 'example.com')
#=> true

## Case-insensitive match returns true
Onetime::Utils::DomainParser.hostname_matches?('EXAMPLE.COM', 'example.com')
#=> true

## Mixed case match returns true
Onetime::Utils::DomainParser.hostname_matches?('ExAmPlE.cOm', 'example.com')
#=> true

## Match with port stripped returns true
Onetime::Utils::DomainParser.hostname_matches?('example.com:443', 'example.com')
#=> true

## Match both with ports returns true
Onetime::Utils::DomainParser.hostname_matches?('example.com:443', 'example.com:8080')
#=> true

## Subdomain does NOT match parent (this is exact matching)
Onetime::Utils::DomainParser.hostname_matches?('sub.example.com', 'example.com')
#=> false

## SECURITY: attacker-controlled domain does NOT match
Onetime::Utils::DomainParser.hostname_matches?('attacker-example.com', 'example.com')
#=> false

## SECURITY: suffix attack does NOT match
Onetime::Utils::DomainParser.hostname_matches?('example.com.attacker.com', 'example.com')
#=> false

## Nil left returns false
Onetime::Utils::DomainParser.hostname_matches?(nil, 'example.com')
#=> false

## Nil right returns false
Onetime::Utils::DomainParser.hostname_matches?('example.com', nil)
#=> false

## Both nil returns false
Onetime::Utils::DomainParser.hostname_matches?(nil, nil)
#=> false

## =================================================================
## hostname_within_domain? - Subdomain checking (SECURITY CRITICAL)
## =================================================================

## Same domain returns true
Onetime::Utils::DomainParser.hostname_within_domain?('example.com', 'example.com')
#=> true

## Direct subdomain returns true
Onetime::Utils::DomainParser.hostname_within_domain?('sub.example.com', 'example.com')
#=> true

## Deep subdomain returns true
Onetime::Utils::DomainParser.hostname_within_domain?('deep.sub.example.com', 'example.com')
#=> true

## Very deep subdomain returns true
Onetime::Utils::DomainParser.hostname_within_domain?('a.b.c.d.example.com', 'example.com')
#=> true

## SECURITY: attacker hyphen domain does NOT match
Onetime::Utils::DomainParser.hostname_within_domain?('attacker-example.com', 'example.com')
#=> false

## SECURITY: domain as subdomain of attacker does NOT match
Onetime::Utils::DomainParser.hostname_within_domain?('example.com.attacker.com', 'example.com')
#=> false

## SECURITY: prefix attack does NOT match
Onetime::Utils::DomainParser.hostname_within_domain?('fakeexample.com', 'example.com')
#=> false

## SECURITY: suffix without dot boundary does NOT match
Onetime::Utils::DomainParser.hostname_within_domain?('notexample.com', 'example.com')
#=> false

## Different TLD does NOT match
Onetime::Utils::DomainParser.hostname_within_domain?('example.org', 'example.com')
#=> false

## Parent domain is NOT within subdomain
Onetime::Utils::DomainParser.hostname_within_domain?('example.com', 'sub.example.com')
#=> false

## Case insensitive subdomain check
Onetime::Utils::DomainParser.hostname_within_domain?('SUB.EXAMPLE.COM', 'example.com')
#=> true

## Port is stripped for subdomain check
Onetime::Utils::DomainParser.hostname_within_domain?('sub.example.com:8080', 'example.com')
#=> true

## Nil hostname returns false
Onetime::Utils::DomainParser.hostname_within_domain?(nil, 'example.com')
#=> false

## Nil domain returns false
Onetime::Utils::DomainParser.hostname_within_domain?('sub.example.com', nil)
#=> false

## =================================================================
## basically_valid? - Format validation
## =================================================================

## Valid simple hostname
Onetime::Utils::DomainParser.basically_valid?('example.com')
#=> true

## Valid subdomain
Onetime::Utils::DomainParser.basically_valid?('sub.example.com')
#=> true

## Valid deep subdomain
Onetime::Utils::DomainParser.basically_valid?('a.b.c.example.com')
#=> true

## Valid with hyphen
Onetime::Utils::DomainParser.basically_valid?('my-domain.com')
#=> true

## Valid localhost
Onetime::Utils::DomainParser.basically_valid?('localhost')
#=> true

## Valid with numbers
Onetime::Utils::DomainParser.basically_valid?('example123.com')
#=> true

## Invalid: nil
Onetime::Utils::DomainParser.basically_valid?(nil)
#=> false

## Invalid: empty string
Onetime::Utils::DomainParser.basically_valid?('')
#=> false

## Invalid: whitespace only
Onetime::Utils::DomainParser.basically_valid?('   ')
#=> false

## Invalid: contains space
Onetime::Utils::DomainParser.basically_valid?('exam ple.com')
#=> false

## Invalid: contains underscore
Onetime::Utils::DomainParser.basically_valid?('exam_ple.com')
#=> false

## Invalid: starts with hyphen
Onetime::Utils::DomainParser.basically_valid?('-example.com')
#=> false

## Invalid: segment starts with hyphen
Onetime::Utils::DomainParser.basically_valid?('sub.-example.com')
#=> false

## Invalid: segment ends with hyphen
Onetime::Utils::DomainParser.basically_valid?('example-.com')
#=> false

## Invalid: too long (over 253 chars)
Onetime::Utils::DomainParser.basically_valid?('a' * 300)
#=> false

## Invalid: too many subdomains (over 10)
Onetime::Utils::DomainParser.basically_valid?('a.b.c.d.e.f.g.h.i.j.k.example.com')
#=> false

## =================================================================
## Edge cases and real-world scenarios
## =================================================================

## Works with co.uk style TLDs
Onetime::Utils::DomainParser.hostname_within_domain?('sub.example.co.uk', 'example.co.uk')
#=> true

## co.uk attacker domain does not match
Onetime::Utils::DomainParser.hostname_within_domain?('attacker-example.co.uk', 'example.co.uk')
#=> false

## Works with URL input for within_domain
Onetime::Utils::DomainParser.hostname_within_domain?('https://api.example.com/webhook', 'example.com')
#=> true

## Webhook URL security check - attacker URL fails
Onetime::Utils::DomainParser.hostname_within_domain?('https://attacker-example.com/webhook', 'example.com')
#=> false
