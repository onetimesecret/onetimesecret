# try/unit/request_logger_sanitization_try.rb
#
# frozen_string_literal: true

# These tryouts validate the #sanitize_for_json helper on
# Onetime::Application::RequestLogger. The helper recursively coerces any
# non-JSON-primitive value (e.g. Rack::Multipart::UploadedFile, Tempfile,
# IO handles) to a String via to_s before the payload reaches
# Familia::JsonSerializer.dump (Oj strict mode).
#
# Without this sanitization step, strict JSON serialization raises on
# unexpected object types when running under :debug capture mode -- taking
# the middleware (and the request) down with it.

require_relative '../support/test_helpers'

OT.boot! :test, false

require 'familia/json_serializer'
require_relative '../../lib/onetime/application/request_logger'

# Minimal Rack app and config to instantiate RequestLogger.
@app    = ->(_env) { [200, {}, ['']] }
@config = { 'capture' => 'debug' }
@logger = Onetime::Application::RequestLogger.new(@app, @config)

# A simple class whose to_s yields a predictable marker. Stand-in for
# arbitrary non-primitive objects like Tempfile, Pathname, custom wrappers.
class SanitizeTargetObject
  def to_s
    'sanitize-target-object-string'
  end
end

# Struct mimicking Rack::Multipart::UploadedFile for the common case that
# motivated the fix: uploaded files surfacing in request.params.
UploadLikeStruct = Struct.new(:filename, :type) do
  def to_s
    "upload(#{filename})"
  end
end

## sanitize_for_json is defined as a private instance method on RequestLogger
@logger.respond_to?(:sanitize_for_json, true)
#=> true

## sanitize_for_json is NOT exposed as a public method
@logger.respond_to?(:sanitize_for_json)
#=> false

## String primitive passes through unchanged
@logger.send(:sanitize_for_json, 'hello')
#=> 'hello'

## Integer primitive passes through unchanged
@logger.send(:sanitize_for_json, 42)
#=> 42

## Float primitive passes through unchanged
@logger.send(:sanitize_for_json, 3.14)
#=> 3.14

## true passes through unchanged
@logger.send(:sanitize_for_json, true)
#=> true

## false passes through unchanged
@logger.send(:sanitize_for_json, false)
#=> false

## nil passes through unchanged
@logger.send(:sanitize_for_json, nil)
#=> nil

## Hash is recursively sanitized, remains a Hash with string keys
input  = { 'a' => 1, 'b' => 'two' }
result = @logger.send(:sanitize_for_json, input)
[result.class, result['a'], result['b']]
#=> [Hash, 1, 'two']

## Symbol keys are stringified so Oj strict mode can serialize them
result = @logger.send(:sanitize_for_json, { method: 'GET' })
[result.keys, result['method']]
#=> [['method'], 'GET']

## Nested Hash values preserved as Hash, not flattened
input  = { 'outer' => { 'inner' => 'value' } }
result = @logger.send(:sanitize_for_json, input)
[result['outer'].class, result['outer']['inner']]
#=> [Hash, 'value']

## Array is recursively sanitized and remains an Array
result = @logger.send(:sanitize_for_json, ['a', 1, true, nil])
[result.class, result]
#=> [Array, ['a', 1, true, nil]]

## Array of mixed primitives and non-primitives coerces only the non-primitives
result = @logger.send(:sanitize_for_json, ['keep', SanitizeTargetObject.new, 7])
result
#=> ['keep', 'sanitize-target-object-string', 7]

## Non-primitive object is coerced to its to_s output
result = @logger.send(:sanitize_for_json, SanitizeTargetObject.new)
result
#=> 'sanitize-target-object-string'

## An UploadedFile-like struct is coerced to a String
upload = UploadLikeStruct.new('photo.png', 'image/png')
result = @logger.send(:sanitize_for_json, upload)
[result.class, result]
#=> [String, 'upload(photo.png)']

## After sanitization, Familia::JsonSerializer.dump does not raise on the upload
upload     = UploadLikeStruct.new('report.pdf', 'application/pdf')
sanitized  = @logger.send(:sanitize_for_json, { 'file' => upload })
# Oj strict mode would raise on the raw struct; sanitized payload must serialize.
json = Familia::JsonSerializer.dump(sanitized)
json.include?('upload(report.pdf)')
#=> true

## Mixed realistic payload serializes successfully end-to-end
upload  = UploadLikeStruct.new('resume.docx', 'application/octet-stream')
payload = {
  method: 'POST',
  params: { 'file' => upload, 'name' => 'x' },
  headers: { 'HTTP_HOST' => 'a.com' },
}
sanitized = @logger.send(:sanitize_for_json, payload)
json      = Familia::JsonSerializer.dump(sanitized)
parsed    = Familia::JsonSerializer.parse(json)
[parsed['method'], parsed['params']['file'], parsed['params']['name'], parsed['headers']['HTTP_HOST']]
#=> ['POST', 'upload(resume.docx)', 'x', 'a.com']

## Deep recursion cuts off with [TOO_DEEP] marker (guard against cycles/huge trees)
deep = { 'a' => { 'b' => { 'c' => { 'd' => { 'e' => { 'f' => { 'g' => { 'h' => { 'i' => { 'j' => { 'k' => 'too-deep' } } } } } } } } } } }
result = @logger.send(:sanitize_for_json, deep)
# After 10 levels, further recursion returns the sentinel string.
Familia::JsonSerializer.dump(result).include?('TOO_DEEP')
#=> true

# -----------------------------------------------------------------------------
# Additional coverage (PR #3012): non-primitive coercion, mixed nesting, keys,
# depth boundary, and mutation safety.
# -----------------------------------------------------------------------------

## IO-like object (StringIO) coerces to to_s output, not raising under strict JSON
require 'stringio'
io     = StringIO.new('hello')
result = @logger.send(:sanitize_for_json, io)
# StringIO#to_s returns the default Object inspect-like form -- what matters is
# that it's a String (so Oj strict doesn't blow up). We only assert the class
# and that JSON serialization succeeds.
[result.class, Familia::JsonSerializer.dump({ 'io' => result }).class]
#=> [String, String]

## Rack::Session::SessionId-like object (no public_id; .to_s returns hex digest)
# Mirrors the real-world cause: SessionId reaches the payload when capture=debug.
class FakeSessionId
  def to_s
    'abcdef0123456789'
  end
end
result = @logger.send(:sanitize_for_json, FakeSessionId.new)
[result.class, result]
#=> [String, 'abcdef0123456789']

## Nested Array inside Hash inside Array recurses at each level
input  = [{ 'list' => ['a', SanitizeTargetObject.new, 2] }]
result = @logger.send(:sanitize_for_json, input)
[result.class, result[0]['list']]
#=> [Array, ['a', 'sanitize-target-object-string', 2]]

## Hash inside Array inside Hash recurses (mixed Hash/Array structure)
input  = { 'items' => [{ 'id' => 1, 'obj' => SanitizeTargetObject.new }] }
result = @logger.send(:sanitize_for_json, input)
[result['items'][0]['id'], result['items'][0]['obj']]
#=> [1, 'sanitize-target-object-string']

## Symbol keys are stringified recursively inside nested Hashes too
input  = { outer: { inner: { deeper: 'ok' } } }
result = @logger.send(:sanitize_for_json, input)
[result.keys, result['outer'].keys, result['outer']['inner'].keys, result['outer']['inner']['deeper']]
#=> [['outer'], ['inner'], ['deeper'], 'ok']

## Numeric (Integer) keys are coerced to strings via k.to_s
input  = { 1 => 'one', 2 => 'two' }
result = @logger.send(:sanitize_for_json, input)
[result.keys.sort, result['1'], result['2']]
#=> [['1', '2'], 'one', 'two']

## Mixed key types in one Hash all coerce to String keys
input  = { :sym => 1, 'str' => 2, 42 => 3 }
result = @logger.send(:sanitize_for_json, input)
result.keys.sort
#=> ['42', 'str', 'sym']

## Array values also participate in depth counting
# Build a structure that's 11 Array-levels deep. At depth > 10 the sentinel fires.
deep_array = 'leaf'
11.times { deep_array = [deep_array] }
result = @logger.send(:sanitize_for_json, deep_array)
Familia::JsonSerializer.dump(result).include?('TOO_DEEP')
#=> true

## Exactly at the depth cap (10 nested hashes), the leaf still serializes
# Structure: depth 0 is root, depth 10 is the innermost 'k'. depth > 10 triggers sentinel.
at_limit = { 'a' => { 'b' => { 'c' => { 'd' => { 'e' => { 'f' => { 'g' => { 'h' => { 'i' => { 'j' => 'leaf' } } } } } } } } } }
result = @logger.send(:sanitize_for_json, at_limit)
json   = Familia::JsonSerializer.dump(result)
[json.include?('TOO_DEEP'), json.include?('leaf')]
#=> [false, true]

## Mixed Hash/Array nesting contributes equally to depth counting
# 5 hashes wrapping 6 arrays = 11 levels; should trigger sentinel.
mixed = 'leaf'
6.times { mixed = [mixed] }
5.times { mixed = { 'k' => mixed } }
result = @logger.send(:sanitize_for_json, mixed)
Familia::JsonSerializer.dump(result).include?('TOO_DEEP')
#=> true

## Original input Hash is not mutated by sanitization (returns a new structure)
input  = { sym: 'v' }
_      = @logger.send(:sanitize_for_json, input)
# Keys on the original should still be Symbols; only the returned Hash is stringified.
input.keys
#=> [:sym]

## Original input Array is not mutated by sanitization (returns a new Array)
obj    = SanitizeTargetObject.new
input  = [obj, 1]
_      = @logger.send(:sanitize_for_json, input)
# First element of the original array is still the raw object, not the stringification.
input.first.equal?(obj)
#=> true

## Empty Hash round-trips to an empty Hash
@logger.send(:sanitize_for_json, {})
#=> {}

## Empty Array round-trips to an empty Array
@logger.send(:sanitize_for_json, [])
#=> []

## Symbol value (not key) is a non-primitive and coerces to its String form
# Symbols are NOT listed in the primitive whenlist, so they go through value.to_s.
result = @logger.send(:sanitize_for_json, :status_ok)
[result.class, result]
#=> [String, 'status_ok']
