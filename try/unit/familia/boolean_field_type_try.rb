# try/unit/familia/boolean_field_type_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Familia::BooleanFieldType — the custom Familia
# field type that canonicalizes boolean-ish values to the strings
# 'true' / 'false' on every read/write path.
#
# Coverage:
#  1. canonicalize/1 — every documented input shape
#  2. Setter coercion — direct assignment normalizes in-memory ivar
#  3. Constructor coercion — Customer.create!(verified: …) goes
#     through the setter
#  4. Fast-writer coercion — verified!(value) persists the canonical
#     form to Redis (this was the historical bypass path)
#  5. Self-healing reads — legacy '1' / '0' values in Redis come back
#     as canonical strings on next load
#  6. Predicate alignment — Customer#verified? returns booleans that
#     match the canonical store

require_relative '../../support/test_helpers'

OT.boot! :test, false

# Convenience alias
BFT = Onetime::Familia::BooleanFieldType

# ---------------------------------------------------------------------------
# 1. canonicalize/1: every documented input shape
# ---------------------------------------------------------------------------

## canonicalize: Ruby true → 'true'
BFT.canonicalize(true)
#=> 'true'

## canonicalize: 'true' (lowercase string) → 'true'
BFT.canonicalize('true')
#=> 'true'

## canonicalize: 'TRUE' (uppercase string) is case-insensitive
BFT.canonicalize('TRUE')
#=> 'true'

## canonicalize: '1' (legacy string aliased as truthy)
BFT.canonicalize('1')
#=> 'true'

## canonicalize: 1 (integer) → 'true'
BFT.canonicalize(1)
#=> 'true'

## canonicalize: 'yes' (third documented alias) → 'true'
BFT.canonicalize('yes')
#=> 'true'

## canonicalize: 'YES' is case-insensitive
BFT.canonicalize('YES')
#=> 'true'

## canonicalize: Ruby false → 'false'
BFT.canonicalize(false)
#=> 'false'

## canonicalize: 'false' string → 'false'
BFT.canonicalize('false')
#=> 'false'

## canonicalize: '0' (legacy string) → 'false'
BFT.canonicalize('0')
#=> 'false'

## canonicalize: 0 (integer zero) → 'false'
BFT.canonicalize(0)
#=> 'false'

## canonicalize: 'no' is NOT in TRUTHY → 'false'
BFT.canonicalize('no')
#=> 'false'

## canonicalize: nil → 'false'
BFT.canonicalize(nil)
#=> 'false'

## canonicalize: empty string → 'false'
BFT.canonicalize('')
#=> 'false'

## canonicalize: arbitrary non-truthy string → 'false'
BFT.canonicalize('definitely-not-true')
#=> 'false'

## TRUTHY constant lists exactly the expected aliases
Onetime::Familia::BooleanFieldType::TRUTHY
#=> ['true', '1', 'yes']

# ---------------------------------------------------------------------------
# 2. Setter coercion — direct assignment normalizes the in-memory ivar
# ---------------------------------------------------------------------------

## cust.verified = true stores canonical 'true'
cust = Onetime::Customer.new(email: generate_random_email)
cust.verified = true
cust.verified
#=> 'true'

## cust.verified = false stores canonical 'false'
cust = Onetime::Customer.new(email: generate_random_email)
cust.verified = false
cust.verified
#=> 'false'

## cust.verified = '1' (legacy) stores canonical 'true'
cust = Onetime::Customer.new(email: generate_random_email)
cust.verified = '1'
cust.verified
#=> 'true'

## cust.verified = 'YES' stores canonical 'true'
cust = Onetime::Customer.new(email: generate_random_email)
cust.verified = 'YES'
cust.verified
#=> 'true'

## cust.verified = 'no' stores canonical 'false'
cust = Onetime::Customer.new(email: generate_random_email)
cust.verified = 'no'
cust.verified
#=> 'false'

## cust.verified = nil stores canonical 'false'
cust = Onetime::Customer.new(email: generate_random_email)
cust.verified = nil
cust.verified
#=> 'false'

# ---------------------------------------------------------------------------
# 3. Constructor coercion — Customer.create!(verified: …) → setter path
# ---------------------------------------------------------------------------

## Customer.create!(verified: true) persists 'true' and round-trips
@create_email = generate_unique_test_email('boolean_field_create_true')
cust = Onetime::Customer.create!(email: @create_email, verified: true)
[cust.verified, Onetime::Customer.find_by_email(@create_email).verified]
#=> ['true', 'true']

## Customer.create!(verified: '1') canonicalizes legacy input on create
@legacy_email = generate_unique_test_email('boolean_field_create_legacy')
cust = Onetime::Customer.create!(email: @legacy_email, verified: '1')
[cust.verified, Onetime::Customer.find_by_email(@legacy_email).verified]
#=> ['true', 'true']

## Customer.create!(verified: false) persists 'false'
@false_email = generate_unique_test_email('boolean_field_create_false')
cust = Onetime::Customer.create!(email: @false_email, verified: false)
[cust.verified, Onetime::Customer.find_by_email(@false_email).verified]
#=> ['false', 'false']

# ---------------------------------------------------------------------------
# 4. Fast writer — the historical bypass path now coerces too
# ---------------------------------------------------------------------------

## cust.verified!(true) persists canonical 'true' to Redis
@fw_email = generate_unique_test_email('boolean_field_fw_true')
cust = Onetime::Customer.create!(email: @fw_email)
cust.verified!(true)
Onetime::Customer.find_by_email(@fw_email).verified
#=> 'true'

## cust.verified!('yes') persists canonical 'true' to Redis
@fw_yes_email = generate_unique_test_email('boolean_field_fw_yes')
cust = Onetime::Customer.create!(email: @fw_yes_email)
cust.verified!('yes')
Onetime::Customer.find_by_email(@fw_yes_email).verified
#=> 'true'

## cust.verified!(false) persists canonical 'false' to Redis
@fw_false_email = generate_unique_test_email('boolean_field_fw_false')
cust = Onetime::Customer.create!(email: @fw_false_email, verified: true)
cust.verified!(false)
Onetime::Customer.find_by_email(@fw_false_email).verified
#=> 'false'

# ---------------------------------------------------------------------------
# 5. Self-healing reads — legacy raw values normalize on load
# ---------------------------------------------------------------------------

## A customer whose verified field was written as '1' directly to
## Redis (simulating data persisted before BooleanFieldType existed)
## comes back as canonical 'true' after load via deserialize.
@legacy_load_email = generate_unique_test_email('boolean_field_legacy_load')
cust = Onetime::Customer.create!(email: @legacy_load_email)
# Force a non-canonical legacy value into Redis directly.
cust.dbclient.hset(cust.dbkey, 'verified', '1')
Onetime::Customer.find_by_email(@legacy_load_email).verified
#=> 'true'

# ---------------------------------------------------------------------------
# 6. Predicate alignment — verified? matches stored form
# ---------------------------------------------------------------------------

## verified? returns true for an authenticated, canonically-true customer
cust = Onetime::Customer.new(email: generate_random_email, role: 'customer')
cust.verified = 'true'
cust.verified?
#=> true

## verified? returns false for a canonically-false customer
cust = Onetime::Customer.new(email: generate_random_email, role: 'customer')
cust.verified = 'false'
cust.verified?
#=> false

## verified? returns false for legacy-coerced 'no'
cust = Onetime::Customer.new(email: generate_random_email, role: 'customer')
cust.verified = 'no'
cust.verified?
#=> false

## verified? still returns false for anonymous role even when verified='true'
cust = Onetime::Customer.new(email: generate_random_email, role: 'anonymous')
cust.verified = 'true'
cust.verified?
#=> false

# ---------------------------------------------------------------------------
# Cleanup — remove the persisted test customers so re-runs stay isolated
# ---------------------------------------------------------------------------

[
  @create_email, @legacy_email, @false_email,
  @fw_email, @fw_yes_email, @fw_false_email,
  @legacy_load_email
].each do |email|
  cust = Onetime::Customer.find_by_email(email)
  cust&.destroy!
rescue StandardError
  # Best-effort cleanup; tryouts aren't expected to leave state behind
  # but a stuck record from a prior failure shouldn't fail this file.
  nil
end
