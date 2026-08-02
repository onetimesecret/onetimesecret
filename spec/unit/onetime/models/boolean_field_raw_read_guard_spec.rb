# spec/unit/onetime/models/boolean_field_raw_read_guard_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Static guard — no bare truthiness reads of boolean_field readers
#            (security audit 2026-07-31, dead-branch finding)
# =============================================================================
#
# `boolean_field` readers return the canonical STRINGS 'true'/'false'
# (Onetime::FieldTypes::BooleanFieldType), so `if cust.verified` type-checks,
# reads naturally, and is ALWAYS truthy — "false" is truthy in Ruby. That
# exact bug made the verification-resend branch in
# apps/api/account/logic/account/create_account.rb unreachable for every
# persisted customer until 2026-07-31. The correct read is the predicate:
# `cust.verified?`.
#
# This spec is the lint the BooleanFieldType docs cannot be: it discovers
# every declared boolean_field in the tree, then fails on any conditional
# read of those attribute names that lacks the `?`. Discovery is dynamic so a
# newly declared field is guarded the moment it exists, with no list to
# maintain here.
#
# Scope and known limits: the scan is name-based, so an unrelated method that
# happens to share a declared field's name would false-positive — acceptable
# for the current field names (verified, suspended), and the failure message
# says how to resolve one. Comments are skipped; multi-line conditions are
# matched per-line.
#
# =============================================================================

require 'spec_helper'

RSpec.describe 'boolean_field raw-read guard' do
  ROOT         = File.expand_path('../../../..', __dir__)
  SOURCE_GLOBS = %w[apps/**/*.rb lib/**/*.rb].freeze
  EXCLUDED     = %r{/(spec|try)/}

  def source_files
    SOURCE_GLOBS.flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }
                .reject { |path| path.match?(EXCLUDED) }
  end

  def declared_boolean_fields
    fields = source_files.flat_map do |path|
      File.read(path).scan(/^\s*(?:base\.)?boolean_field\s+:(\w+)/).flatten
    end.uniq.sort
    raise 'Guard is broken: found no boolean_field declarations in the tree' if fields.empty?

    fields
  end

  # A read is "bare" when the field name is used as a truthiness test without
  # the predicate `?`. Two alternates cover the forms seen in review:
  #
  #   1. `.field` preceded on the same line by a conditional keyword
  #      (if/elsif/unless/until/while — leading OR trailing statement-modifier) or a
  #      boolean operator (&&, ||, !), with optional opening paren(s) between
  #      them: `if cust.verified`, `return if cust.verified`,
  #      `if (cust.verified)`, `x && cust.verified`, `!cust.verified`.
  #   2. Ternary: `.field` followed by whitespace then `?` —
  #      `cust.verified ? a : b`. The space is what separates the ternary
  #      operator from the predicate: `verified?` has no space before `?` and
  #      stays excluded.
  #
  # Still excluded: predicate reads (`verified?`), chained calls
  # (`.verified.to_s`), explicit `==`/`!=` comparisons, assignments
  # (`.verified = true` — no conditional context and no ternary `?`), and
  # symbol/string literals (no receiver dot).
  def bare_read_pattern(fields)
    names = fields.join('|')
    /
      (?:
        (?: \b(?:if|elsif|unless|until|while)\s+ | && \s* | \|\| \s* | ! ) [(\s]*
        [\w@.\[\]']* \. (?:#{names})
        (?! [?\w.] | \s*[=!]= )
      |
        [\w@.\[\]']* \. (?:#{names})
        [ \t]+ \? (?![?\w])
      )
    /x
  end

  it 'has no bare conditional reads of declared boolean_field attributes' do
    fields  = declared_boolean_fields
    pattern = bare_read_pattern(fields)

    offenses = source_files.flat_map do |path|
      File.read(path).each_line.with_index(1).filter_map do |line, lineno|
        next if line.strip.start_with?('#')
        next unless line.match?(pattern)

        "#{path.delete_prefix("#{ROOT}/")}:#{lineno}: #{line.strip}"
      end
    end

    expect(offenses).to be_empty, <<~MSG
      Bare truthiness read of a boolean_field. These readers return the STRINGS
      'true'/'false' (BooleanFieldType), so the condition is always truthy —
      "false" is truthy in Ruby. Use the predicate (e.g. `verified?`) instead.
      If a hit is an unrelated method that merely shares a declared field name
      (#{fields.join(', ')}), rename one of them or adjust this guard.

      #{offenses.join("\n")}
    MSG
  end

  it 'matches the known bare-read forms and excludes safe reads (pattern self-test)' do
    pattern = bare_read_pattern(%w[verified suspended])

    flagged = [
      'if cust.verified',                 # leading keyword
      'elsif cust.verified',              # elsif branch
      'return if cust.verified',          # trailing statement-modifier
      'if (cust.verified)',               # parenthesized receiver
      'unless (@cust.verified)',          # ivar + paren
      'do_thing unless cust.verified',    # trailing unless
      'cust.verified ? a : b',            # ternary, no keyword at all
      'x = @cust.verified ? "y" : "n"',   # ternary in assignment RHS
      'ok && cust.verified',              # boolean operator
      '!cust.suspended',                  # negation
      '!(cust.suspended)',                # negated paren
    ]
    not_flagged = [
      'if cust.verified?',                # predicate
      'return if cust.verified?',         # trailing predicate
      "cust.verified.to_s == 'true'",     # chained call
      "if cust.verified == 'true'",       # explicit comparison
      "raise if cust.verified != 'true'", # explicit negated comparison
      'cust.verified = true',             # assignment
      'cust.verified? ? a : b',           # predicate + ternary
      'field == :verified',               # symbol literal
    ]

    misses = flagged.reject { |line| line.match?(pattern) }
    expect(misses).to be_empty, "pattern failed to flag: #{misses.inspect}"

    false_positives = not_flagged.select { |line| line.match?(pattern) }
    expect(false_positives).to be_empty, "pattern wrongly flagged: #{false_positives.inspect}"
  end
end
