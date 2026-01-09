# try/security/output_escaper_try.rb
#
# frozen_string_literal: true

# Security Tests: Output Escaping (Onetime::Security::OutputEscaper)
#
# These tests verify that the output escaper properly handles various value types
# for safe rendering in views and JSON responses.
#
# The OutputEscaper module provides:
# - escape_for_output: HTML-escape strings/symbols, pass through arrays/hashes
# - normalize_value: legacy alias for escape_for_output
#
# Key behaviors:
# - HTTPS URLs should NOT be escaped (safe for rendering)
# - HTML special characters in strings should be escaped
# - Arrays and Hashes pass through unchanged
# - Nil returns nil
# - Unsupported types return empty string and log error

require_relative '../support/test_helpers'

# Require the security module explicitly (loaded via utils.rb)
require 'onetime/security/output_escaper'

OT.boot! :test, false

# Create a test class that extends the escaper for testing
class TestOutputEscaper
  extend Onetime::Security::OutputEscaper
end

## escape_for_output: escapes HTML special characters in strings
TestOutputEscaper.escape_for_output('<script>alert("xss")</script>')
#=> '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;'

## escape_for_output: escapes ampersand
TestOutputEscaper.escape_for_output('Tom & Jerry')
#=> 'Tom &amp; Jerry'

## escape_for_output: escapes less than and greater than
TestOutputEscaper.escape_for_output('1 < 2 > 0')
#=> '1 &lt; 2 &gt; 0'

## escape_for_output: escapes double quotes
TestOutputEscaper.escape_for_output('Say "hello"')
#=> 'Say &quot;hello&quot;'

## escape_for_output: escapes single quotes
TestOutputEscaper.escape_for_output("It's fine")
#=> 'It&#39;s fine'

## escape_for_output: handles empty string
TestOutputEscaper.escape_for_output('')
#=> ''

## escape_for_output: HTTPS URLs are NOT escaped
TestOutputEscaper.escape_for_output('https://example.com/path?query=1&other=2')
#=> 'https://example.com/path?query=1&other=2'

## escape_for_output: HTTPS URL with special characters preserved
url = 'https://example.com/search?q=<test>&page=1'
TestOutputEscaper.escape_for_output(url)
#=> 'https://example.com/search?q=<test>&page=1'

## escape_for_output: HTTPS URL with unicode preserved
TestOutputEscaper.escape_for_output('https://example.com/')
#=> 'https://example.com/'

## escape_for_output: HTTP URLs ARE escaped (not secure)
result = TestOutputEscaper.escape_for_output('http://example.com/path?a=1&b=2')
result.include?('&amp;')
#=> true

## escape_for_output: handles Symbol input
TestOutputEscaper.escape_for_output(:hello_world)
#=> 'hello_world'

## escape_for_output: escapes HTML in Symbol
TestOutputEscaper.escape_for_output(:"<b>bold</b>")
#=> '&lt;b&gt;bold&lt;/b&gt;'

## escape_for_output: handles Integer input
TestOutputEscaper.escape_for_output(42)
#=> '42'

## escape_for_output: handles Float input
TestOutputEscaper.escape_for_output(3.14159)
#=> '3.14159'

## escape_for_output: handles negative numbers
TestOutputEscaper.escape_for_output(-100)
#=> '-100'

## escape_for_output: passes through Array unchanged
arr = ['item1', 'item2', '<script>']
TestOutputEscaper.escape_for_output(arr)
#=> ['item1', 'item2', '<script>']

## escape_for_output: Array identity check
arr = [1, 2, 3]
TestOutputEscaper.escape_for_output(arr).object_id == arr.object_id
#=> true

## escape_for_output: passes through Hash unchanged
hash = { key: 'value', html: '<b>bold</b>' }
TestOutputEscaper.escape_for_output(hash)
#=> { key: 'value', html: '<b>bold</b>' }

## escape_for_output: Hash identity check
hash = { a: 1 }
TestOutputEscaper.escape_for_output(hash).object_id == hash.object_id
#=> true

## escape_for_output: handles true
TestOutputEscaper.escape_for_output(true)
#=> true

## escape_for_output: handles false
TestOutputEscaper.escape_for_output(false)
#=> false

## escape_for_output: handles nil
TestOutputEscaper.escape_for_output(nil)
#=> nil

## escape_for_output: nested XSS attempt
TestOutputEscaper.escape_for_output('<img src=x onerror=alert(1)>')
#=> '&lt;img src=x onerror=alert(1)&gt;'

## escape_for_output: javascript protocol
TestOutputEscaper.escape_for_output('javascript:alert(1)')
#=> 'javascript:alert(1)'

## escape_for_output: data URL (not HTTPS, should be escaped if contains HTML chars)
result = TestOutputEscaper.escape_for_output('data:text/html,<script>alert(1)</script>')
result.include?('&lt;')
#=> true

## normalize_value: is an alias for escape_for_output
TestOutputEscaper.normalize_value('<b>test</b>')
#=> '&lt;b&gt;test&lt;/b&gt;'

## normalize_value: HTTPS URL preserved
TestOutputEscaper.normalize_value('https://secure.example.com/')
#=> 'https://secure.example.com/'

## Integration: OutputEscaper is extended into Utils
Onetime::Utils.respond_to?(:escape_for_output)
#=> true

## Integration: Utils.escape_for_output works correctly
Onetime::Utils.escape_for_output('<div>test</div>')
#=> '&lt;div&gt;test&lt;/div&gt;'

## Integration: Utils.escape_for_output preserves HTTPS
Onetime::Utils.escape_for_output('https://onetimesecret.com/')
#=> 'https://onetimesecret.com/'

## Integration: Utils has normalize_value alias
Onetime::Utils.respond_to?(:normalize_value)
#=> true

## Edge case: malformed URL that looks like HTTPS
result = TestOutputEscaper.escape_for_output('https://<script>')
result.include?('&lt;')
#=> true

## Edge case: HTTPS URL with fragments
TestOutputEscaper.escape_for_output('https://example.com/page#section')
#=> 'https://example.com/page#section'

## Edge case: HTTPS URL with credentials (should still preserve)
TestOutputEscaper.escape_for_output('https://user:pass@example.com/')
#=> 'https://user:pass@example.com/'

## Edge case: mixed case HTTPS is still valid URI
TestOutputEscaper.escape_for_output('HTTPS://EXAMPLE.COM/')
#=> 'HTTPS://EXAMPLE.COM/'
