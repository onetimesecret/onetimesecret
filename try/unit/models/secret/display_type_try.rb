# try/unit/models/secret/display_type_try.rb
#
# frozen_string_literal: true

# Secret display_type feature: a presentation hint for the recipient's
# client, stamped at creation (Receipt.spawn_pair) and normalized at the read
# boundary (display_type_or_default / safe_dump). Records created before
# the field existed, values this build does not know, and types the platform
# has turned off (features.markdown.enabled, default off) read as 'text'.
# See docs/specs/secret-display-type.md.

require_relative '../../../support/test_models'

OT.boot! :test, true

# Markdown is opt-in per platform; turn it on for the cases that store and
# read it, and off again in the cases that check the gate. Restored at the end.
@original_markdown              = OT.conf['features']['markdown']
OT.conf['features']['markdown'] = { 'enabled' => true }

## The display_type feature is enabled on Secret
Onetime::Secret.features_enabled.include?(:display_type)
#=> true

## display_types is the closed value space, plain text first
Onetime::Secret.display_types
#=> ['text', 'markdown']

## default_display_type is plain text
Onetime::Secret.default_display_type
#=> 'text'

## The field has no fast writer: the type is stamped once at creation
[Onetime::Secret.fields.include?(:display_type), Onetime::Secret.method_defined?(:display_type!)]
#=> [true, false]

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

## normalize_display_type strips and downcases; absent or blank means text
[
  Onetime::Secret.normalize_display_type(' Markdown '),
  Onetime::Secret.normalize_display_type('  '),
  Onetime::Secret.normalize_display_type(nil),
  Onetime::Secret.normalize_display_type('httplink'),
]
#=> ['markdown', 'text', 'text', 'httplink']

## An unset display_type reads as text (every pre-field record)
secret = Onetime::Secret.new
[secret.display_type, secret.display_type_or_default, secret.display_type?(:text)]
#=> [nil, 'text', true]

## A stored markdown display_type reads back as markdown
secret = Onetime::Secret.new display_type: 'markdown'
[secret.display_type_or_default, secret.display_type?(:markdown), secret.display_type?('text')]
#=> ['markdown', true, false]

## A stored value this build does not know reads as text and is left as stored
secret = Onetime::Secret.new display_type: 'httplink'
[secret.display_type_or_default, secret.display_type?(:markdown), secret.display_type]
#=> ['text', false, 'httplink']

## spawn_pair stores the display type on the secret and safe_dump exposes it
_receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, '# hello', display_type: 'markdown'
reloaded         = Onetime::Secret.load secret.identifier
[reloaded.display_type, reloaded.safe_dump[:display_type]]
#=> ['markdown', 'markdown']

## spawn_pair without a display type leaves the field unset; safe_dump still says text
_receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, 'plain'
reloaded         = Onetime::Secret.load secret.identifier
[reloaded.display_type, reloaded.safe_dump[:display_type]]
#=> [nil, 'text']

## safe_dump carries display_type before reveal: it describes how to show the
## value, not what the value is, so no plaintext travels with it
_receipt, secret = Onetime::Receipt.spawn_pair 'anon', 3600, '# hello', display_type: 'markdown'
dump             = secret.safe_dump
[dump[:display_type], dump.key?(:secret_value), dump.key?(:ciphertext)]
#=> ['markdown', false, false]

## display_type_enabled? offers text always and markdown only when the platform turns it on
enabled_on                      = [Onetime::Secret.display_type_enabled?('text'), Onetime::Secret.display_type_enabled?(:markdown)]
OT.conf['features']['markdown'] = { 'enabled' => false }
enabled_off                     = [Onetime::Secret.display_type_enabled?('text'), Onetime::Secret.display_type_enabled?(:markdown)]
OT.conf['features'].delete('markdown')
enabled_absent                  = Onetime::Secret.display_type_enabled?('markdown')
OT.conf['features']['markdown'] = { 'enabled' => 'true' }
enabled_string                  = Onetime::Secret.display_type_enabled?('markdown')
OT.conf['features']['markdown'] = { 'enabled' => true }
[enabled_on, enabled_off, enabled_absent, enabled_string]
#=> [[true, true], [true, false], false, true]

## display_type_enabled? is false for unknown and blank values whatever the flags say
OT.conf['features']['httplink'] = { 'enabled' => true }
result                          = [Onetime::Secret.display_type_enabled?('httplink'), Onetime::Secret.display_type_enabled?('')]
OT.conf['features'].delete('httplink')
result
#=> [false, false]

## With markdown off, a stored markdown secret reads and dumps as text, and the stored value stays
_receipt, secret                = Onetime::Receipt.spawn_pair 'anon', 3600, '# hello', display_type: 'markdown'
OT.conf['features']['markdown'] = { 'enabled' => false }
reloaded                        = Onetime::Secret.load secret.identifier
result                          = [reloaded.display_type, reloaded.display_type_or_default, reloaded.safe_dump[:display_type]]
OT.conf['features']['markdown'] = { 'enabled' => true }
result
#=> ['markdown', 'text', 'text']

## Turning markdown back on shows the same secret as markdown again
_receipt, secret                = Onetime::Receipt.spawn_pair 'anon', 3600, '# hello', display_type: 'markdown'
OT.conf['features']['markdown'] = { 'enabled' => false }
off                             = Onetime::Secret.load(secret.identifier).safe_dump[:display_type]
OT.conf['features']['markdown'] = { 'enabled' => true }
on                              = Onetime::Secret.load(secret.identifier).safe_dump[:display_type]
[off, on]
#=> ['text', 'markdown']

OT.conf['features']['markdown'] = @original_markdown
