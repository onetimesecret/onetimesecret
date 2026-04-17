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
