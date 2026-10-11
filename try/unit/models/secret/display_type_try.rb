# try/unit/models/secret/display_type_try.rb
#
# frozen_string_literal: true

# Secret#display_type: a presentation hint for the recipient's client,
# stamped at creation (Receipt.spawn_pair) and normalized at the read
# boundary (display_type_or_default / safe_dump). Records created before
# the field existed, and values this build does not know, read as 'text'.
# See docs/specs/secret-display-type.md.

require_relative '../../../support/test_models'

OT.boot! :test, true

## DISPLAY_TYPES is the closed value space, plain text first
Onetime::Secret::DISPLAY_TYPES
#=> ['text', 'markdown']

## DEFAULT_DISPLAY_TYPE is plain text
Onetime::Secret::DEFAULT_DISPLAY_TYPE
#=> 'text'

## valid_display_type? accepts known values given as strings or symbols
[Onetime::Secret.valid_display_type?('markdown'), Onetime::Secret.valid_display_type?(:text)]
#=> [true, true]

## valid_display_type? rejects unknown, blank and nil values
[
  Onetime::Secret.valid_display_type?('httplink'),
  Onetime::Secret.valid_display_type?(''),
  Onetime::Secret.valid_display_type?(nil),
]
#=> [false, false, false]

## An unset display_type reads as text (every pre-field record)
secret = Onetime::Secret.new
[secret.display_type, secret.display_type_or_default, secret.markdown?]
#=> [nil, 'text', false]

## A stored markdown display_type reads back as markdown
secret = Onetime::Secret.new display_type: 'markdown'
[secret.display_type_or_default, secret.markdown?]
#=> ['markdown', true]

## A stored value this build does not know falls back to text rather than raising
secret = Onetime::Secret.new display_type: 'httplink'
[secret.display_type_or_default, secret.markdown?]
#=> ['text', false]

## spawn_pair stores the display type on the secret and safe_dump exposes it
_receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, '# hello', display_type: 'markdown'
reloaded = Onetime::Secret.load secret.identifier
[reloaded.display_type, reloaded.safe_dump[:display_type]]
#=> ['markdown', 'markdown']

## spawn_pair without a display type leaves the field unset; safe_dump still says text
_receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'plain'
reloaded = Onetime::Secret.load secret.identifier
[reloaded.display_type, reloaded.safe_dump[:display_type]]
#=> [nil, 'text']

## safe_dump carries display_type before reveal: it describes how to show the
## value, not what the value is, so no plaintext travels with it
_receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, '# hello', display_type: 'markdown'
dump = secret.safe_dump
[dump[:display_type], dump.key?(:secret_value), dump.key?(:ciphertext)]
#=> ['markdown', false, false]
