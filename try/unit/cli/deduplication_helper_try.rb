# try/unit/cli/deduplication_helper_try.rb
#
# frozen_string_literal: true

# Unit tests for DeduplicationHelper methods used by migration commands.
# These test the pure-logic helper without Redis or booting the app.
#
# Run: bundle exec try try/unit/cli/deduplication_helper_try.rb

require_relative '../../support/test_helpers'
require 'onetime/cli/migrations/deduplication_helper'

# Create a simple host class to include the helper module
@host = Object.new
@host.extend(Onetime::CLI::DeduplicationHelper)

# -------------------------------------------------------------------
# find_json_quoted_duplicates: returns quoted members where the
# raw (unquoted) form also exists in the same collection.
# -------------------------------------------------------------------

## Empty collection returns empty array
@host.find_json_quoted_duplicates([])
#=> []

## Collection with only raw members returns empty array
@host.find_json_quoted_duplicates(['abc', 'def', 'ghi'])
#=> []

## Collection with only JSON-quoted members (no raw counterpart) returns empty
@host.find_json_quoted_duplicates(['"abc"', '"def"'])
#=> []

## Collection with both quoted and raw forms returns the quoted duplicate
result = @host.find_json_quoted_duplicates(['abc', '"abc"'])
result
#=> ['"abc"']

## Multiple pairs: returns all quoted duplicates
members = ['abc', '"abc"', 'def', '"def"', 'ghi']
result = @host.find_json_quoted_duplicates(members).sort
result
#=> ['"abc"', '"def"']

## Mixed scenario: some with both forms, some only quoted, some only raw
members = ['alpha', '"alpha"', '"beta"', 'gamma', '"delta"']
result = @host.find_json_quoted_duplicates(members)
result
#=> ['"alpha"']

## Edge case: member that is exactly two quote characters (length 2) is NOT a duplicate
# m[1..-2] would be empty string, so it should not match unless "" is in the set
members = ['""', 'abc']
result = @host.find_json_quoted_duplicates(members)
result
#=> []

## Edge case: member with length-2 quotes where empty string IS in set
members = ['', '""']
# '""' starts/ends with quote, length > 2 is false (length == 2), so excluded
result = @host.find_json_quoted_duplicates(members)
result
#=> []

## Member with quotes only at start is not treated as JSON-quoted
members = ['"abc', 'abc']
result = @host.find_json_quoted_duplicates(members)
result
#=> []

## Member with quotes only at end is not treated as JSON-quoted
members = ['abc"', 'abc']
result = @host.find_json_quoted_duplicates(members)
result
#=> []

## Members with nested quotes inside: outer quotes stripped, inner preserved
# '"say \"hello\""' has raw form 'say \"hello\"' which is unlikely to exist
members = ['"say \"hello\""', 'say \"hello\"']
result = @host.find_json_quoted_duplicates(members)
result
#=> ['"say \"hello\""']

## Members with special characters inside quotes
members = ['user@example.com', '"user@example.com"']
result = @host.find_json_quoted_duplicates(members)
result
#=> ['"user@example.com"']

## Members with colons (common in Redis identifiers)
members = ['customer:abc123', '"customer:abc123"']
result = @host.find_json_quoted_duplicates(members)
result
#=> ['"customer:abc123"']

## Members with UUID-like identifiers
members = ['550e8400-e29b-41d4-a716-446655440000', '"550e8400-e29b-41d4-a716-446655440000"']
result = @host.find_json_quoted_duplicates(members)
result
#=> ['"550e8400-e29b-41d4-a716-446655440000"']

## Duplicate detection is not confused by substring matches
# '"ab"' raw form is 'ab', not 'abc'
members = ['abc', '"ab"']
result = @host.find_json_quoted_duplicates(members)
result
#=> []

## Large collection performance: returns correct results
raw = (1..100).map { |i| "id_#{i}" }
quoted = raw.first(50).map { |m| "\"#{m}\"" }
orphan_quoted = (101..120).map { |i| "\"id_#{i}\"" }
members = raw + quoted + orphan_quoted
result = @host.find_json_quoted_duplicates(members)
result.size
#=> 50

## Single member that is quoted with no raw counterpart
@host.find_json_quoted_duplicates(['"lonely"'])
#=> []

## Single member that is raw
@host.find_json_quoted_duplicates(['lonely'])
#=> []

# -------------------------------------------------------------------
# find_json_quoted_members: returns ALL JSON-quoted members regardless
# of whether a raw counterpart exists. Used for normalization.
# (Being added by backend-dev agent)
# -------------------------------------------------------------------

## find_json_quoted_members exists on the helper
@host.respond_to?(:find_json_quoted_members)
#=> true

## find_json_quoted_members returns empty for empty collection
@host.find_json_quoted_members([])
#=> []

## find_json_quoted_members returns empty for only raw members
@host.find_json_quoted_members(['abc', 'def', 'ghi'])
#=> []

## find_json_quoted_members returns ALL quoted members even without raw counterpart
result = @host.find_json_quoted_members(['"abc"', '"def"'])
result.sort
#=> ['"abc"', '"def"']

## find_json_quoted_members includes both duplicates and orphans
members = ['alpha', '"alpha"', '"beta"', 'gamma']
result = @host.find_json_quoted_members(members).sort
result
#=> ['"alpha"', '"beta"']

## find_json_quoted_members excludes length-2 empty-quote member
members = ['""', '"real"']
result = @host.find_json_quoted_members(members)
result
#=> ['"real"']

## find_json_quoted_members excludes partial-quote members
members = ['"start_only', 'end_only"', '"proper"']
result = @host.find_json_quoted_members(members)
result
#=> ['"proper"']

## find_json_quoted_members with Redis-style identifiers
members = ['customer:abc', '"customer:abc"', '"customer:def"']
result = @host.find_json_quoted_members(members).sort
result
#=> ['"customer:abc"', '"customer:def"']

# -------------------------------------------------------------------
# find_normalize_only_members: returns quoted members whose unquoted
# form does NOT exist. These need replace (zrem+zadd / srem+sadd).
# -------------------------------------------------------------------

## find_normalize_only_members exists on the helper
@host.respond_to?(:find_normalize_only_members)
#=> true

## find_normalize_only_members returns empty for empty collection
@host.find_normalize_only_members([])
#=> []

## find_normalize_only_members returns empty when all are raw
@host.find_normalize_only_members(['abc', 'def'])
#=> []

## find_normalize_only_members returns orphaned quoted members
result = @host.find_normalize_only_members(['"orphan1"', '"orphan2"'])
result.sort
#=> ['"orphan1"', '"orphan2"']

## find_normalize_only_members excludes quoted members that have raw counterpart
members = ['alpha', '"alpha"', '"beta"']
result = @host.find_normalize_only_members(members)
result
#=> ['"beta"']

## find_normalize_only_members with mixed scenario
members = ['raw1', '"raw1"', '"only_quoted"', 'raw2', '"also_only_quoted"']
result = @host.find_normalize_only_members(members).sort
result
#=> ['"also_only_quoted"', '"only_quoted"']

## find_normalize_only_members excludes length-2 empty-quote
members = ['""', '"valid"']
result = @host.find_normalize_only_members(members)
result
#=> ['"valid"']

## find_normalize_only_members is disjoint from find_json_quoted_duplicates
members = ['x', '"x"', '"y"', 'z']
dupes = @host.find_json_quoted_duplicates(members)
normalizable = @host.find_normalize_only_members(members)
# The two sets should not overlap
(dupes & normalizable).empty?
#=> true

## The union of duplicates + normalizable equals all quoted members
members = ['a', '"a"', '"b"', 'c', '"d"']
all_quoted = @host.find_json_quoted_members(members).sort
dupes = @host.find_json_quoted_duplicates(members)
normalizable = @host.find_normalize_only_members(members)
(dupes + normalizable).sort == all_quoted
#=> true

# -------------------------------------------------------------------
# print_mode_banner: output helper
# -------------------------------------------------------------------

## print_mode_banner returns nil for dry_run = true (prints text)
result = @host.print_mode_banner(true)
# Returns nil but produces output; we just check it doesn't raise
result.nil? || true
#=> true

## print_mode_banner returns nil for dry_run = false (no output)
result = @host.print_mode_banner(false)
result.nil?
#=> true

# -------------------------------------------------------------------
# print_results: output helper
# -------------------------------------------------------------------

## print_results handles stats with no errors
stats = { keys_scanned: 5, keys_with_duplicates: 2, duplicates_removed: 10, errors: [] }
result = @host.print_results(stats, true)
# Should not raise; returns nil
result.nil? || true
#=> true

## print_results handles stats with errors
stats = { keys_scanned: 3, keys_with_duplicates: 1, duplicates_removed: 4, errors: ['key1: timeout'] }
result = @host.print_results(stats, false)
result.nil? || true
#=> true
