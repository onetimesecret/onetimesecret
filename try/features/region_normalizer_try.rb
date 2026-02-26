#!/usr/bin/env ruby

# frozen_string_literal: true

# RegionNormalizer Unit Tests (Issue #2554)
#
# Tests the Billing::RegionNormalizer module which centralizes
# region string normalization and comparison. This is the foundation
# for all four billing region isolation fixes.
#
# The normalizer prevents nil/blank/case mismatches that caused:
#   - Products from wrong regions leaking into catalog pushes
#   - nil.to_s -> "" erasing Stripe metadata
#   - Config-only plans losing their region assignment
#   - Boot-time plan loading ignoring region filters

require_relative '../support/test_helpers'
require_relative '../../apps/web/billing/region_normalizer'

# ---------------------------------------------------------------------------
# .normalize — nil/blank handling
# ---------------------------------------------------------------------------

## normalize(nil) returns nil
Billing::RegionNormalizer.normalize(nil)
#=> nil

## normalize("") returns nil (empty string treated as blank)
Billing::RegionNormalizer.normalize("")
#=> nil

## normalize("  ") returns nil (whitespace-only treated as blank)
Billing::RegionNormalizer.normalize("  ")
#=> nil

## normalize("\t\n") returns nil (other whitespace treated as blank)
Billing::RegionNormalizer.normalize("\t\n")
#=> nil

# ---------------------------------------------------------------------------
# .normalize — case normalization
# ---------------------------------------------------------------------------

## normalize("nz") upcases to "NZ"
Billing::RegionNormalizer.normalize("nz")
#=> "NZ"

## normalize("NZ") preserves already-upcased value
Billing::RegionNormalizer.normalize("NZ")
#=> "NZ"

## normalize("Nz") handles mixed case
Billing::RegionNormalizer.normalize("Nz")
#=> "NZ"

# ---------------------------------------------------------------------------
# .normalize — whitespace stripping
# ---------------------------------------------------------------------------

## normalize(" nz ") strips leading/trailing whitespace before upcasing
Billing::RegionNormalizer.normalize(" nz ")
#=> "NZ"

## normalize("  EU  ") strips multiple spaces
Billing::RegionNormalizer.normalize("  EU  ")
#=> "EU"

## normalize(" us_east ") handles underscore region codes
Billing::RegionNormalizer.normalize(" us_east ")
#=> "US_EAST"

# ---------------------------------------------------------------------------
# .match? — same region comparison
# ---------------------------------------------------------------------------

## match?("nz", "NZ") returns true (case-insensitive match)
Billing::RegionNormalizer.match?("nz", "NZ")
#=> true

## match?("NZ", "NZ") returns true (identical values)
Billing::RegionNormalizer.match?("NZ", "NZ")
#=> true

## match?(" nz ", "NZ") returns true (whitespace stripped before compare)
Billing::RegionNormalizer.match?(" nz ", "NZ")
#=> true

# ---------------------------------------------------------------------------
# .match? — fail-closed when deployment region is configured
# ---------------------------------------------------------------------------

## match?(nil, "NZ") returns false (nil product region rejected when deployment has region)
Billing::RegionNormalizer.match?(nil, "NZ")
#=> false

## match?("", "NZ") returns false (blank product region rejected when deployment has region)
Billing::RegionNormalizer.match?("", "NZ")
#=> false

## match?("  ", "NZ") returns false (whitespace product region rejected when deployment has region)
Billing::RegionNormalizer.match?("  ", "NZ")
#=> false

# ---------------------------------------------------------------------------
# .match? — pass-through when no deployment region configured
# ---------------------------------------------------------------------------

## match?("NZ", nil) returns true (no deployment region = accept all)
Billing::RegionNormalizer.match?("NZ", nil)
#=> true

## match?(nil, nil) returns true (no deployment region = accept all)
Billing::RegionNormalizer.match?(nil, nil)
#=> true

# ---------------------------------------------------------------------------
# .match? — different region rejection
# ---------------------------------------------------------------------------

## match?("NZ", "US") returns false (different regions)
Billing::RegionNormalizer.match?("NZ", "US")
#=> false

## match?("EU", "NZ") returns false (different regions)
Billing::RegionNormalizer.match?("EU", "NZ")
#=> false

## match?("nz", "us") returns false (case-insensitive, still different)
Billing::RegionNormalizer.match?("nz", "us")
#=> false

## match?(" CA ", " NZ ") returns false (stripped, still different)
Billing::RegionNormalizer.match?(" CA ", " NZ ")
#=> false

# ---------------------------------------------------------------------------
# .match? — symmetric blank-second-arg (deployment side)
# ---------------------------------------------------------------------------

## match?("NZ", "") returns true (blank deployment region = pass-through)
Billing::RegionNormalizer.match?("NZ", "")
#=> true

## match?("NZ", "  ") returns true (whitespace deployment region = pass-through)
Billing::RegionNormalizer.match?("NZ", "  ")
#=> true

# ---------------------------------------------------------------------------
# .normalize — non-String input (Symbol from YAML loader)
# ---------------------------------------------------------------------------

## normalize(:nz) handles Symbol input via to_s
Billing::RegionNormalizer.normalize(:nz)
#=> "NZ"

## normalize(:EU) handles uppercase Symbol
Billing::RegionNormalizer.normalize(:EU)
#=> "EU"

# ---------------------------------------------------------------------------
# .match? — double-nil fallback (no region anywhere)
# ---------------------------------------------------------------------------

## match?("", nil) returns true (blank product, no deployment region)
Billing::RegionNormalizer.match?("", nil)
#=> true

## match?("", "") returns true (both blank = both normalize to nil)
Billing::RegionNormalizer.match?("", "")
#=> true
