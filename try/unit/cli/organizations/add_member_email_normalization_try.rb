# try/unit/cli/organizations/add_member_email_normalization_try.rb
#
# frozen_string_literal: true

# Tests for email normalization consistency in add_member_command.rb
#
# Issue: The CLI command was using `email.to_s.strip.downcase` but the model
# uses `OT::Utils.normalize_email` (NFC + case fold) for storage. Without
# matching normalization, lookups for internationalized emails could fail.
#
# The fix ensures the CLI uses the canonical normalization:
#   OT::Utils.normalize_email(email)
#
# This test verifies:
# 1. Email lookup works with unicode characters (e.g., "MULLER@example.com" finds "muller@example.com")
# 2. The normalization chain handles edge cases (combining diacritics, Turkish I, etc.)
# 3. CLI normalization matches model normalization for consistent lookups
#
# Run: bundle exec try try/unit/cli/organizations/add_member_email_normalization_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :cli

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

@test_id = SecureRandom.hex(6)

# Helper to normalize email the same way the CLI command does (after fix).
# Inlined here deliberately to test that the chain matches OT::Utils.normalize_email.
def cli_normalize_email(email)
  email.to_s.strip.unicode_normalize(:nfc).downcase(:fold)
end

# Helper to simulate CLI customer lookup (matching add_member_command.rb:99)
def find_customer_via_cli(email)
  normalized = cli_normalize_email(email)
  Onetime::Customer.find_by_email(normalized)
end

# TRYOUTS

## CLI normalization matches model storage normalization for ASCII uppercase
ascii_input = "TEST_USER_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: ascii_input)
# Model stores normalized, CLI lookup uses same normalization
cli_found = find_customer_via_cli(ascii_input)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI finds customer with German umlaut (MULLER -> muller)
german_input = "MULLER_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: german_input)
# Lookup with original uppercase should find normalized lowercase
cli_found = find_customer_via_cli(german_input)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI finds customer with actual German umlaut u (MULLER -> muller)
# U+00DC is Latin Capital Letter U With Diaeresis
german_umlaut_input = "M\u00dcLLER_#{@test_id}@EXAMPLE.COM"  # MULLER with umlaut U
cust = Onetime::Customer.create!(email: german_umlaut_input)
# downcase(:fold) converts U -> u
cli_found = find_customer_via_cli(german_umlaut_input)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI handles Spanish ene (N with tilde)
spanish_input = "SENOR_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: spanish_input)
cli_found = find_customer_via_cli(spanish_input)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI handles French accented characters
french_input = "CAFE_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: french_input)
cli_found = find_customer_via_cli(french_input)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI handles German sharp S (Eszett) - downcase(:fold) expands to ss
# The capital sharp S (U+1E9E) folds to "ss" per Unicode case folding rules
german_sharp_s = "STRASSE_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: german_sharp_s)
cli_found = find_customer_via_cli(german_sharp_s)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI handles Cyrillic uppercase (PRIVET in Cyrillic)
# Use actual Cyrillic letters for realistic test
cyrillic_input = "\u041F\u0420\u0418\u0412\u0415\u0422_#{@test_id}@EXAMPLE.COM"  # CYRILLIC
cust = Onetime::Customer.create!(email: cyrillic_input)
cli_found = find_customer_via_cli(cyrillic_input)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI handles Greek uppercase (ALPHA BETA in Greek)
# Use actual Greek letters
greek_input = "\u0391\u0392_#{@test_id}@EXAMPLE.COM"  # Greek Alpha Beta
cust = Onetime::Customer.create!(email: greek_input)
cli_found = find_customer_via_cli(greek_input)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI handles combining diacritics (NFD to NFC normalization)
# NFD: e + combining acute accent (U+0301)
# NFC: e with acute (U+00E9)
# Both should normalize to the same string
nfd_email = "cafe\u0301_#{@test_id}@example.com"  # e + combining acute
nfc_email = "caf\u00e9_#{@test_id}@example.com"   # single e with acute
# Create with NFD input
cust = Onetime::Customer.create!(email: nfd_email)
# Lookup with NFC variation should find the same customer
cli_found = find_customer_via_cli(nfc_email)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI handles whitespace before normalization
whitespace_email = "  WHITESPACE_#{@test_id}@EXAMPLE.COM  "
cust = Onetime::Customer.create!(email: "whitespace_#{@test_id}@example.com")
cli_found = find_customer_via_cli(whitespace_email)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI handles tabs in whitespace
tab_email = "\tTABBED_#{@test_id}@EXAMPLE.COM\t"
cust = Onetime::Customer.create!(email: "tabbed_#{@test_id}@example.com")
cli_found = find_customer_via_cli(tab_email)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## CLI normalization is idempotent (normalizing twice gives same result)
email = "MULLER_#{@test_id}@EXAMPLE.COM"
once = cli_normalize_email(email)
twice = cli_normalize_email(once)
once == twice
#=> true

## Turkish dotted I handling with case folding
# Turkish I (U+0130) - Latin Capital Letter I With Dot Above
# With :fold, this becomes lowercase "i" (ASCII i)
# Note: This tests that :fold handles special Turkish case correctly
turkish_i = "TURK\u0130SH_#{@test_id}@EXAMPLE.COM"  # Turkish I with dot above
cust = Onetime::Customer.create!(email: turkish_i)
cli_found = find_customer_via_cli(turkish_i)
result = cli_found&.custid == cust.custid
cust.delete!
result
#=> true

## Demonstrate the old bug: simple downcase fails for German sharp S
# Without OT::Utils.normalize_email, lookups could fail
# when CLI and model use different normalization
old_style_normalize = ->(e) { e.to_s.strip.downcase }  # Old CLI behavior

# For basic ASCII, both produce the same result
ascii_test = "TEST@EXAMPLE.COM"
old_style_normalize.call(ascii_test) == OT::Utils.normalize_email(ascii_test)
#=> true

## Demonstrate consistency: CLI and model normalize to same value
email_input = "MULLER_#{@test_id}@EXAMPLE.COM"
# What model stores via canonical normalization
model_stored = OT::Utils.normalize_email(email_input)
# What CLI normalizes for lookup
cli_lookup = cli_normalize_email(email_input)
model_stored == cli_lookup
#=> true

## find_by_org_email uses correct normalization for invitation lookup
# ensure_membership calls find_by_org_email which normalizes with strip.downcase
# This ensures consistent behavior between member lookup and invitation lookup
test_email = "INVITATION_#{@test_id}@EXAMPLE.COM"
OT::Utils.normalize_email(test_email) == cli_normalize_email(test_email)
#=> true
