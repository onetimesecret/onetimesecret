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

  it 'has no bare conditional reads of declared boolean_field attributes' do
    fields  = declared_boolean_fields
    # A read is "bare" when the field name follows a receiver inside a
    # conditional context (if/unless/leading or trailing, &&, ||, !) without
    # the predicate `?`. `= `-writes, `.to_s` comparisons, and symbol/string
    # literals do not match because the pattern requires `.field` preceded by
    # a conditional keyword or boolean operator on the same line. Chained
    # calls (`.verified.to_s`) and explicit `==`/`!=` comparisons are
    # excluded — those handle the string form deliberately.
    pattern = /
      (?: \b(?:if|unless|until|while)\s+ | && \s* | \|\| \s* | ! )
      [\w@.\[\]']* \. (?:#{fields.join('|')})
      (?! [?\w.] | \s*[=!]= )
    /x

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
end
