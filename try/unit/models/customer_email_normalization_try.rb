# try/unit/models/customer_email_normalization_try.rb
#
# frozen_string_literal: true

# Tests for email case normalization in Customer.create!
#
# Issue #2843: Email addresses must be stored consistently lowercase in Redis
# because Redis hash keys are case-sensitive. PostgreSQL uses citext for
# case-insensitive lookups, but Redis (unique_index :email) requires exact match.
#
# Tests cover:
# 1. Customer.create! normalizes uppercase emails to lowercase
# 2. Customer.create! normalizes mixed-case emails to lowercase
# 3. Customer.create! strips whitespace from emails
# 4. Customer.create! handles combined case and whitespace issues
# 5. find_by_email works with normalized stored email
# 6. Duplicate detection works regardless of input case

require_relative '../../support/test_helpers'

OT.boot! :test, false

@test_id = SecureRandom.hex(6)

# TRYOUTS

## Customer.create! normalizes UPPERCASE email to lowercase
uppercase_email = "UPPERCASE_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: uppercase_email)
stored_email = cust.email
cust.delete!
stored_email
#=> "uppercase_#{@test_id}@example.com"

## Customer.create! normalizes MixedCase email to lowercase
mixed_email = "MixedCase_#{@test_id}@Example.COM"
cust = Onetime::Customer.create!(email: mixed_email)
stored_email = cust.email
cust.delete!
stored_email
#=> "mixedcase_#{@test_id}@example.com"

## Customer.create! strips leading whitespace from email
whitespace_email = "  leading_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: whitespace_email)
stored_email = cust.email
cust.delete!
stored_email
#=> "leading_#{@test_id}@example.com"

## Customer.create! strips trailing whitespace from email
whitespace_email = "trailing_#{@test_id}@example.com  "
cust = Onetime::Customer.create!(email: whitespace_email)
stored_email = cust.email
cust.delete!
stored_email
#=> "trailing_#{@test_id}@example.com"

## Customer.create! handles combined uppercase and whitespace
combined_email = "  COMBINED_#{@test_id}@EXAMPLE.COM  "
cust = Onetime::Customer.create!(email: combined_email)
stored_email = cust.email
cust.delete!
stored_email
#=> "combined_#{@test_id}@example.com"

## Customer.create! handles tabs in whitespace
tab_email = "\tTABBED_#{@test_id}@EXAMPLE.COM\t"
cust = Onetime::Customer.create!(email: tab_email)
stored_email = cust.email
cust.delete!
stored_email
#=> "tabbed_#{@test_id}@example.com"

## find_by_email finds customer stored with normalized email using lowercase lookup
normalized_email = "findtest_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: "FINDTEST_#{@test_id}@EXAMPLE.COM")
found = Onetime::Customer.find_by_email(normalized_email)
result = found&.custid == cust.custid
cust.delete!
result
#=> true

## find_by_email does NOT find customer when lookup uses uppercase (Redis is case-sensitive)
# This demonstrates why normalization at storage time is critical
normalized_email = "casesense_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: normalized_email)
# Redis index stores lowercase, uppercase lookup fails
found_uppercase = Onetime::Customer.find_by_email("CASESENSE_#{@test_id}@EXAMPLE.COM")
result = found_uppercase.nil?
cust.delete!
result
#=> true

## email_exists? returns true for lowercase lookup when stored via uppercase input
check_email = "exists_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: "EXISTS_#{@test_id}@EXAMPLE.COM")
exists_result = Onetime::Customer.email_exists?(check_email)
cust.delete!
exists_result
#=> true

## Customer.create! raises RecordExistsError for duplicate uppercase when lowercase exists
dup_email = "duplicate_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: dup_email)
begin
  Onetime::Customer.create!(email: "DUPLICATE_#{@test_id}@EXAMPLE.COM")
rescue Familia::RecordExistsError => e
  result = e.message.include?('Customer exists')
ensure
  cust.delete!
end
result
#=> true

## Customer.create! with positional email argument also normalizes
positional_email = "POSITIONAL_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(positional_email)
stored_email = cust.email
cust.delete!
stored_email
#=> "positional_#{@test_id}@example.com"

# =============================================================================
# Unicode Email Normalization Tests (Issue #2843)
# =============================================================================
#
# These tests verify proper handling of international email addresses using:
#   - NFC normalization for consistent Unicode representation
#   - :fold for proper case folding of international characters
#
# Example: "ÑOÑO@EXAMPLE.COM" -> "ñoño@example.com"
#
# The :fold parameter to String#downcase handles special cases like:
#   - German sharp S (ß -> ss in some contexts)
#   - Turkish dotless i (İ -> i with fold, not I)
#   - Greek letters with different upper/lower forms

## Customer.create! normalizes Unicode uppercase (Spanish ñ)
unicode_spanish = "SEÑOR_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: unicode_spanish)
stored_email = cust.email
cust.delete!
stored_email
#=> "señor_#{@test_id}@example.com"

## Customer.create! normalizes Unicode with accented characters
unicode_accents = "CAFÉ_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: unicode_accents)
stored_email = cust.email
cust.delete!
stored_email
#=> "café_#{@test_id}@example.com"

## Customer.create! normalizes German sharp S with case folding
# Note: downcase(:fold) converts uppercase ẞ to "ss" per Unicode case folding rules
# This is correct behavior - full case folding expands ẞ to ss for compatibility
german_email = "STRAẞE_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: german_email)
stored_email = cust.email
cust.delete!
stored_email
#=> "strasse_#{@test_id}@example.com"

## Customer.create! handles Greek uppercase letters
greek_email = "ΕΛΛΗΝΙΚΆ_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: greek_email)
stored_email = cust.email
cust.delete!
stored_email
#=> "ελληνικά_#{@test_id}@example.com"

## Customer.create! handles Cyrillic uppercase letters
cyrillic_email = "ПРИВЕТ_#{@test_id}@EXAMPLE.COM"
cust = Onetime::Customer.create!(email: cyrillic_email)
stored_email = cust.email
cust.delete!
stored_email
#=> "привет_#{@test_id}@example.com"

## Customer.create! applies NFC normalization (composed form)
# The same character can be represented differently in Unicode:
# - NFD (decomposed): é = e + ́ (combining acute accent)
# - NFC (composed): é = é (single codepoint)
# NFC normalization ensures consistent storage for duplicate detection
nfd_email = "nfctest_cafe\u0301_#{@test_id}@example.com"  # e + combining acute
cust = Onetime::Customer.create!(email: nfd_email)
stored_email = cust.email
# After NFC normalization, should be composed form
is_nfc_normalized = stored_email == stored_email.unicode_normalize(:nfc)
cust.delete!
is_nfc_normalized
#=> true

## Duplicate detection works with NFC vs NFD variations of same email
# First create with NFC (composed) form
nfc_email = "caf\u00e9_nfc_#{@test_id}@example.com"  # single é codepoint
cust = Onetime::Customer.create!(email: nfc_email)
begin
  # Try to create with NFD (decomposed) form - should be detected as duplicate
  nfd_variation = "cafe\u0301_nfc_#{@test_id}@example.com"  # e + combining acute
  Onetime::Customer.create!(email: nfd_variation)
rescue Familia::RecordExistsError => e
  result = e.message.include?('Customer exists')
ensure
  cust.delete!
end
result
#=> true
