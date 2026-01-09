# try/security/input_sanitizers_try.rb
#
# frozen_string_literal: true

# Security Tests: Input Sanitization (Onetime::Security::InputSanitizers)
#
# These tests verify that the centralized input sanitization methods properly
# handle various input types and malicious patterns.
#
# The InputSanitizers module provides:
# - sanitize_identifier: strict allowlist for IDs (alphanumeric, underscore, hyphen)
# - sanitize_plain_text: strip HTML, normalize whitespace, optional max_length
# - sanitize_email: strip HTML, lowercase, trim whitespace
#
# These methods are included in Onetime::Logic::Base for use in logic classes.

require_relative '../support/test_helpers'

# Require the security module explicitly
require 'onetime/security/input_sanitizers'

OT.boot! :test, false

# Create a test class that includes the sanitizers for testing
class TestSanitizer
  include Onetime::Security::InputSanitizers
end

@sanitizer = TestSanitizer.new

## sanitize_identifier: allows alphanumeric characters
@sanitizer.sanitize_identifier('abc123')
#=> 'abc123'

## sanitize_identifier: allows uppercase letters
@sanitizer.sanitize_identifier('ABC123xyz')
#=> 'ABC123xyz'

## sanitize_identifier: allows underscores
@sanitizer.sanitize_identifier('my_identifier_123')
#=> 'my_identifier_123'

## sanitize_identifier: allows hyphens
@sanitizer.sanitize_identifier('my-identifier-123')
#=> 'my-identifier-123'

## sanitize_identifier: strips spaces
@sanitizer.sanitize_identifier('my identifier')
#=> 'myidentifier'

## sanitize_identifier: strips special characters
@sanitizer.sanitize_identifier('abc!@#$%^&*()+=123')
#=> 'abc123'

## sanitize_identifier: strips HTML tags
@sanitizer.sanitize_identifier('<script>alert("xss")</script>id')
#=> 'scriptalertxssscriptid'

## sanitize_identifier: strips SQL injection attempts
@sanitizer.sanitize_identifier("'; DROP TABLE users; --")
#=> 'DROPTABLEusers--'

## sanitize_identifier: handles nil input
@sanitizer.sanitize_identifier(nil)
#=> ''

## sanitize_identifier: handles empty string
@sanitizer.sanitize_identifier('')
#=> ''

## sanitize_identifier: handles numeric input
@sanitizer.sanitize_identifier(12345)
#=> '12345'

## sanitize_identifier: strips null byte unicode
@sanitizer.sanitize_identifier("abc\u0000def")
#=> 'abcdef'

## sanitize_identifier: strips emoji
@sanitizer.sanitize_identifier('test-id-with-🎉-emoji')
#=> 'test-id-with--emoji'

## sanitize_plain_text: preserves normal text
@sanitizer.sanitize_plain_text('Hello World')
#=> 'Hello World'

## sanitize_plain_text: strips HTML tags
@sanitizer.sanitize_plain_text('<b>Bold</b> text')
#=> 'Bold text'

## sanitize_plain_text: strips script tags
@sanitizer.sanitize_plain_text('<script>alert("xss")</script>Safe content')
#=> 'Safe content'

## sanitize_plain_text: strips all HTML including attributes
@sanitizer.sanitize_plain_text('<a href="javascript:alert(1)">Click me</a>')
#=> 'Click me'

## sanitize_plain_text: normalizes multiple spaces
@sanitizer.sanitize_plain_text('Hello    World')
#=> 'Hello World'

## sanitize_plain_text: normalizes tabs and newlines
@sanitizer.sanitize_plain_text("Hello\t\n\rWorld")
#=> 'Hello World'

## sanitize_plain_text: trims leading/trailing whitespace
@sanitizer.sanitize_plain_text('  Hello World  ')
#=> 'Hello World'

## sanitize_plain_text: handles nil input
@sanitizer.sanitize_plain_text(nil)
#=> ''

## sanitize_plain_text: handles empty string
@sanitizer.sanitize_plain_text('')
#=> ''

## sanitize_plain_text: respects max_length option
@sanitizer.sanitize_plain_text('This is a long string', max_length: 10)
#=> 'This is a '

## sanitize_plain_text: max_length with HTML stripping
@sanitizer.sanitize_plain_text('<b>Bold</b> and more text', max_length: 8)
#=> 'Bold and'

## sanitize_plain_text: max_length nil returns full text
@sanitizer.sanitize_plain_text('Full text here', max_length: nil)
#=> 'Full text here'

## sanitize_plain_text: handles img onerror XSS pattern
@sanitizer.sanitize_plain_text('<img src=x onerror=alert(1)>')
#=> ''

## sanitize_plain_text: handles nested tags
@sanitizer.sanitize_plain_text('<div><span><b>Nested</b></span></div>')
#=> 'Nested'

## sanitize_plain_text: strips style tags
@sanitizer.sanitize_plain_text('<style>body{display:none}</style>Visible')
#=> 'Visible'

## sanitize_plain_text: handles HTML entities (decoded by Sanitize)
result = @sanitizer.sanitize_plain_text('&lt;script&gt;')
result.include?('script')
#=> true

## sanitize_email: lowercases email
@sanitizer.sanitize_email('User@Example.COM')
#=> 'user@example.com'

## sanitize_email: trims whitespace
@sanitizer.sanitize_email('  user@example.com  ')
#=> 'user@example.com'

## sanitize_email: strips HTML tags
@sanitizer.sanitize_email('<script>x</script>user@example.com')
#=> 'user@example.com'

## sanitize_email: handles nil input
@sanitizer.sanitize_email(nil)
#=> ''

## sanitize_email: handles empty string
@sanitizer.sanitize_email('')
#=> ''

## sanitize_email: handles email with plus addressing
@sanitizer.sanitize_email('User+Tag@Example.com')
#=> 'user+tag@example.com'

## sanitize_email: handles email with periods in local part
@sanitizer.sanitize_email('First.Last@Example.com')
#=> 'first.last@example.com'

## sanitize_email: preserves valid email structure
@sanitizer.sanitize_email('test.user+filter@sub.domain.example.com')
#=> 'test.user+filter@sub.domain.example.com'

## sanitize_email: strips newlines (prevents header injection)
# Newlines are stripped to prevent email header injection attacks
@sanitizer.sanitize_email("user@example.com\nBcc: attacker@evil.com")
#=> 'user@example.combcc: attacker@evil.com'

## sanitize_email: handles unicode in email (normalized by Sanitize)
result = @sanitizer.sanitize_email('user@example.com')
result.include?('@')
#=> true

## Integration: InputSanitizers module exists and can be included
# Full integration with Logic::Base is tested elsewhere when OT.boot! :app is used
Onetime::Security::InputSanitizers.is_a?(Module)
#=> true
