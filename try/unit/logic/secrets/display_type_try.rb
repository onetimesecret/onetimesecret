# try/unit/logic/secrets/display_type_try.rb
#
# frozen_string_literal: true

# V2 display_type request handling (DisplayTypeParam, included by
# BaseSecretAction; V3 inherits it):
# - absent or blank -> 'text'; otherwise normalized (strip, downcase)
# - an unknown value is a FormError at creation (validate_display_type),
#   not a silent fallback the recipient would see
# - so is a known type the platform has not turned on
#   (features.markdown.enabled, default off)
# - a nested-array shape is rejected as a payload error in process_params
# - GenerateSecret ignores the field: a generated value is always text

require_relative '../../../support/test_helpers'

OT.boot! :test, false

require 'v2/logic'

@anon = MockStrategyResult.anonymous

# Markdown is opt-in per platform; on for these cases unless one says
# otherwise. Restored at the end.
@original_markdown              = OT.conf['features']['markdown']
OT.conf['features']['markdown'] = { 'enabled' => true }

## display_type defaults to text when the request omits it
logic = V2::Logic::Secrets::ConcealSecret.new(@anon, { 'secret' => { 'secret' => 's' } }, 'en')
logic.display_type
#=> 'text'

## A blank display_type reads as text
params = { 'secret' => { 'secret' => 's', 'display_type' => '  ' } }
logic  = V2::Logic::Secrets::ConcealSecret.new(@anon, params, 'en')
logic.display_type
#=> 'text'

## display_type is normalized: surrounding whitespace and case are dropped
params = { 'secret' => { 'secret' => 's', 'display_type' => ' Markdown ' } }
logic  = V2::Logic::Secrets::ConcealSecret.new(@anon, params, 'en')
logic.display_type
#=> 'markdown'

## A known display_type passes validate_display_type
params = { 'secret' => { 'secret' => 's', 'display_type' => 'markdown' } }
logic  = V2::Logic::Secrets::ConcealSecret.new(@anon, params, 'en')
begin
  logic.send(:validate_display_type)
  'no_error'
rescue Onetime::FormError => ex
  "unexpected_error: #{ex.message}"
end
#=> 'no_error'

## An unknown display_type is a FormError naming the field
params = { 'secret' => { 'secret' => 's', 'display_type' => 'httplink' } }
logic  = V2::Logic::Secrets::ConcealSecret.new(@anon, params, 'en')
begin
  logic.send(:validate_display_type)
  'unexpected_success'
rescue Onetime::FormError => ex
  [ex.message, ex.field, ex.error_type]
end
#=> ['Unknown display type: httplink', :display_type, :invalid]

## markdown is a FormError naming the field when the platform has not turned it on
OT.conf['features']['markdown'] = { 'enabled' => false }
params                          = { 'secret' => { 'secret' => 's', 'display_type' => 'markdown' } }
logic                           = V2::Logic::Secrets::ConcealSecret.new(@anon, params, 'en')
result                          = begin
  logic.send(:validate_display_type)
  'unexpected_success'
rescue Onetime::FormError => ex
  [ex.message, ex.field, ex.error_type]
end
OT.conf['features']['markdown'] = { 'enabled' => true }
result
#=> ['Display type not enabled: markdown', :display_type, :invalid]

## text passes validate_display_type with markdown off
OT.conf['features']['markdown'] = { 'enabled' => false }
params                          = { 'secret' => { 'secret' => 's', 'display_type' => 'text' } }
logic                           = V2::Logic::Secrets::ConcealSecret.new(@anon, params, 'en')
result                          = begin
  logic.send(:validate_display_type)
  'no_error'
rescue Onetime::FormError => ex
  "unexpected_error: #{ex.message}"
end
OT.conf['features']['markdown'] = { 'enabled' => true }
result
#=> 'no_error'

## A nested-array display_type is rejected as a payload shape error at construction
params = { 'secret' => { 'secret' => 's', 'display_type' => ['markdown'] } }
begin
  V2::Logic::Secrets::ConcealSecret.new(@anon, params, 'en')
  'unexpected_success'
rescue Onetime::FormError => ex
  [ex.message, ex.field]
end
#=> ['Incorrect payload format', :display_type]

## form_fields echoes the resolved display_type
params = { 'secret' => { 'secret' => 's', 'display_type' => 'markdown' } }
logic  = V2::Logic::Secrets::ConcealSecret.new(@anon, params, 'en')
logic.form_fields[:display_type]
#=> 'markdown'

## GenerateSecret ignores a requested display_type: generated values are always text
params = { 'secret' => { 'display_type' => 'markdown' } }
logic  = V2::Logic::Secrets::GenerateSecret.new(@anon, params, 'en')
logic.display_type
#=> 'text'

OT.conf['features']['markdown'] = @original_markdown
