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

## Extract hostname returns nil for malformed URL (no host)
Onetime::Utils::DomainParser.extract_hostname('https://')
#=> nil

## Extract hostname returns nil for URL with only credentials
Onetime::Utils::DomainParser.extract_hostname('http://user:pass@')
#=> nil

## Extract hostname returns nil for scheme-only URL
Onetime::Utils::DomainParser.extract_hostname('ftp://')
#=> nil

## =================================================================
## file:// URL handling (SECURITY CRITICAL)
## =================================================================
## file:// URLs are used for local filesystem access and should not
## produce hostnames that could be confused with network hosts.
## Per RFC 8089, "localhost" in file:// URIs means local machine.

## file:// with triple slash (local file) returns nil
Onetime::Utils::DomainParser.extract_hostname('file:///path/to/file')
#=> nil

## file:// with localhost returns nil (RFC 8089: localhost = local machine)
Onetime::Utils::DomainParser.extract_hostname('file://localhost/path')
#=> nil

## file:// with LOCALHOST (case variation) returns nil
Onetime::Utils::DomainParser.extract_hostname('file://LOCALHOST/path/to/file')
#=> nil

## file:// with empty host returns nil
Onetime::Utils::DomainParser.extract_hostname('file://')
#=> nil

## file:// with actual remote host extracts hostname
Onetime::Utils::DomainParser.extract_hostname('file://fileserver.example.com/share/doc.txt')
#=> 'fileserver.example.com'

## file:// with IP-like remote host extracts it
Onetime::Utils::DomainParser.extract_hostname('file://192.168.1.1/share')
#=> '192.168.1.1'

## file:// Windows-style UNC path returns nil (no valid host)
Onetime::Utils::DomainParser.extract_hostname('file:///C:/Users/test')
#=> nil

## file:// with port (unusual but valid) extracts hostname
Onetime::Utils::DomainParser.extract_hostname('file://server.local:445/share')
#=> 'server.local'

## =================================================================
## Other URI schemes (SECURITY CRITICAL)
## =================================================================
## Various URI schemes that should be handled safely

## data: URI returns nil (no hostname concept)
Onetime::Utils::DomainParser.extract_hostname('data:text/html,<h1>Hello</h1>')
#=> nil

## javascript: URI returns nil
Onetime::Utils::DomainParser.extract_hostname('javascript:alert(1)')
#=> nil

## mailto: URI returns nil (no hostname)
Onetime::Utils::DomainParser.extract_hostname('mailto:user@example.com')
#=> nil

## tel: URI returns nil
Onetime::Utils::DomainParser.extract_hostname('tel:+1-555-555-5555')
#=> nil

## ftp:// with hostname extracts it
Onetime::Utils::DomainParser.extract_hostname('ftp://ftp.example.com/pub/file.txt')
#=> 'ftp.example.com'

## sftp:// with hostname extracts it
Onetime::Utils::DomainParser.extract_hostname('sftp://secure.example.com/files')
#=> 'secure.example.com'

## ws:// WebSocket URL extracts hostname
Onetime::Utils::DomainParser.extract_hostname('ws://socket.example.com/stream')
#=> 'socket.example.com'

## wss:// secure WebSocket URL extracts hostname
Onetime::Utils::DomainParser.extract_hostname('wss://secure-socket.example.com:8443/stream')
#=> 'secure-socket.example.com'

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

## =================================================================
## Cache functionality (Concurrent::Map)
## =================================================================

## Cache has entries after earlier tests (proves caching is active)
Onetime::Utils::DomainParser.cache_stats[:size] > 0
#=> true

## Cache returns correct max_size constant
Onetime::Utils::DomainParser.cache_stats[:max_size]
#=> 1000

## Clear cache and verify it empties
before_clear = Onetime::Utils::DomainParser.cache_stats[:size]
Onetime::Utils::DomainParser.clear_cache
after_clear = Onetime::Utils::DomainParser.cache_stats[:size]
[before_clear > 0, after_clear]
#=> [true, 0]

## Cache populates after hostname_within_domain? call
Onetime::Utils::DomainParser.clear_cache
Onetime::Utils::DomainParser.hostname_within_domain?('sub.cached-test.com', 'cached-test.com')
Onetime::Utils::DomainParser.cache_stats[:size] > 0
#=> true

## Repeated calls use cached results (size stays constant for same domains)
Onetime::Utils::DomainParser.clear_cache
# First call parses and caches
result1 = Onetime::Utils::DomainParser.hostname_within_domain?('api.example.com', 'example.com')
size_after_first = Onetime::Utils::DomainParser.cache_stats[:size]
# Second call with same domains should hit cache (size unchanged)
result2 = Onetime::Utils::DomainParser.hostname_within_domain?('api.example.com', 'example.com')
size_after_second = Onetime::Utils::DomainParser.cache_stats[:size]
[result1, result2, size_after_first == size_after_second]
#=> [true, true, true]
