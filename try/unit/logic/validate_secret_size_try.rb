# try/unit/logic/validate_secret_size_try.rb
#
# frozen_string_literal: true

# C5: validate_secret_size enforces the content ceiling in BYTES, not
# characters. Multibyte content can occupy up to 4x its character count in
# Redis, so a string that is under the character count but over the byte cap
# must be rejected. An ASCII string exactly at the cap must still pass.

require_relative '../../support/test_logic'

OT.boot! :test, false

@strategy_result = MockStrategyResult.new(session: {}, user: nil)

class SizeTestLogic < Logic::Base
  def process_params; end
  def success_data; { status: 'ok' }; end
  def form_fields; {}; end

  # Expose the protected helper for direct testing.
  def check_size(value)
    validate_secret_size(value)
  end
end

# Pin the ceiling to a small, known value for the byte-boundary assertions.
# Tryout files share one process and OT.conf is global; snapshot first so the
# teardown can restore it for later files.
@max = 8
@saved_conf = YAML.load(YAML.dump(OT.conf))
new_conf = YAML.load(YAML.dump(OT.conf))
new_conf['site']['secret_options'] ||= {}
new_conf['site']['secret_options']['content'] = { 'maximum_length' => @max }
OT.send(:conf=, new_conf)

@obj = SizeTestLogic.new(@strategy_result, {})

## An ASCII string exactly at the cap passes (bytesize == cap)
@obj.check_size('x' * @max)
#=> nil

## An ASCII string one byte over the cap is rejected
begin
  @obj.check_size('x' * (@max + 1))
  false
rescue OT::FormError => e
  e.message.include?('no more than') && e.message.include?('bytes')
end
#=> true

## A multibyte string UNDER the character count but OVER the byte cap is rejected
## (each 'é' is 2 bytes in UTF-8: 5 chars = 5 < 8 cap by chars, but 10 bytes > 8)
multibyte = 'é' * 5
[multibyte.length, multibyte.bytesize]
#=> [5, 10]

## The multibyte string above raises (byte-measured), proving char-count would have passed
begin
  @obj.check_size('é' * 5)
  false
rescue OT::FormError
  true
end
#=> true

## A multibyte string at the byte cap passes (4 * 'é' = 8 bytes == cap)
@obj.check_size('é' * 4)
#=> nil

## Empty content is not the size check's concern (presence handled elsewhere)
@obj.check_size('')
#=> nil

## The rejection message is byte-denominated
begin
  @obj.check_size('x' * (@max + 1))
  'no-error'
rescue OT::FormError => e
  e.message
end
#=> "Secret content must be no more than #{@max} bytes long"

# Restore the shared config for later tryout files.
OT.send(:conf=, @saved_conf)
