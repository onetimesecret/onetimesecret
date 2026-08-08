# lib/onetime/domain_validation/record_matcher.rb
#
# frozen_string_literal: true

require_relative 'record_normalizer'

module Onetime
  module DomainValidation
    # RecordMatcher - shared DNS record matching for both DNS pipelines.
    #
    # Two pipelines compare expected DNS records against live DNS results:
    # the VERIFICATION pipeline (DomainValidation::SenderStrategies) and the
    # FACT-FINDING pipeline (Mail::SenderStrategies). Duplicating the
    # comparison logic between them produced twin bugs (#4023 / #4047), so
    # both delegate here. Pure functions only: no logging, no state, no I/O.
    #
    # Dispatch discipline by record type:
    # - TXT: content-aware. SPF records match on the include: mechanism,
    #   DMARC/DKIM tag-lists match via RecordNormalizer subset comparison,
    #   and opaque provider tokens require an exact match after trim.
    #   Expected values are NOT globally downcased — DKIM p= base64 key
    #   data is case-sensitive (RFC 6376 Section 3.2).
    # - CNAME/MX: hostname comparison, case-insensitive with trailing dots
    #   stripped (RFC 4343).
    # - Anything else: never matches.
    #
    module RecordMatcher
      extend self

      # Check whether the expected value appears in the actual DNS results.
      #
      # @param type [String] Record type (TXT, CNAME, MX)
      # @param expected [String] Expected value
      # @param actual_values [Array<String>] DNS results
      # @return [Boolean]
      def record_matches?(type, expected, actual_values)
        case type
        when 'TXT'
          txt_record_matches?(expected.to_s.strip, actual_values)
        when 'CNAME', 'MX'
          normalized_expected = expected.to_s.downcase.chomp('.')
          actual_values.any? { |v| v.downcase.chomp('.') == normalized_expected }
        else
          false
        end
      end

      # Check whether a TXT record matches expected value.
      #
      # Dispatch (issue #4023):
      # - SPF (v=spf1): spf_record_matches? — customers commonly merge
      #   multiple provider includes into one SPF record, so we extract the
      #   include: directive and verify it appears in any actual SPF record.
      # - DMARC/DKIM tag-lists (v=DMARC1 / v=DKIM1): RecordNormalizer
      #   subset comparison per RFC 6376 Section 3.2 grammar. Raw string
      #   comparison false-negatives on semantically identical records
      #   ("v=DMARC1; p=none;" vs "v=DMARC1;p=none").
      # - Anything else (opaque provider verification tokens): exact match
      #   after trim. Deliberately tighter than the old substring check.
      #
      # @param expected [String] Expected value, trimmed
      # @param actual_values [Array<String>] DNS results
      # @return [Boolean]
      def txt_record_matches?(expected, actual_values)
        if RecordNormalizer.spf?(expected)
          spf_record_matches?(expected.downcase, actual_values)
        elsif RecordNormalizer.tag_list?(expected)
          actual_values.any? { |v| RecordNormalizer.subset_match?(expected, v) }
        else
          actual_values.any? { |v| v.strip == expected }
        end
      end

      # Check whether an SPF record matches expected value.
      #
      # Comparison is term-wise, never substring. An SPF record is a
      # whitespace-separated term list (RFC 7208 Section 4.6.1), so
      # `include:amazonses.com` must appear as a whole term: a zone
      # containing `include:amazonses.com.evil` is a different mechanism
      # and must not verify.
      #
      # When the expected record carries an include: directive we require
      # only that term, so customers can merge several provider includes
      # into one record. Without an include: (a provider using only mx,
      # a:, or redirect=) we require every expected term to be present —
      # the same tolerance, applied to the whole term list. Substring
      # containment would false-negative `v=spf1 mx -all` against a zone
      # holding `v=spf1 mx include:other.com -all`.
      #
      # @param normalized_expected [String] Downcased expected SPF value
      # @param actual_values [Array<String>] DNS results
      # @return [Boolean]
      def spf_record_matches?(normalized_expected, actual_values)
        expected_terms = spf_terms(normalized_expected)
        spf_include    = expected_terms.find { |term| term.start_with?('include:') }
        required_terms = spf_include ? [spf_include] : expected_terms

        return false if required_terms.empty?

        actual_values.any? do |v|
          downcased = v.downcase
          next false unless downcased.start_with?('v=spf1')

          actual_terms = spf_terms(downcased)
          required_terms.all? { |term| actual_terms.include?(term) }
        end
      end

      # Split an SPF record into its whitespace-separated terms
      # (RFC 7208 Section 4.6.1). Callers pass downcased input.
      #
      # @param record [String] Downcased SPF record
      # @return [Array<String>]
      def spf_terms(record)
        record.to_s.split(/\s+/).reject(&:empty?)
      end

      # Filter a TXT result set down to records relevant to the expected
      # value. Only DMARC and SPF expectations have a discriminator; other
      # types and TXT purposes pass through unfiltered.
      #
      # RFC 7489 Section 6.6.3 (DMARC) and RFC 7208 Section 4.5 (SPF) both
      # require record-set selection before evaluation: filter the TXT set
      # by discriminator, discard unrelated records, and treat more than
      # one surviving record as ambiguous — never a pass. A duplicate DMARC
      # or SPF record fails at receiving MTAs, so reporting it verified
      # would be a false green (issue #4023).
      #
      # Zero survivors keeps existing not-found semantics (no match, no
      # error). One survivor plus unrelated TXT records still verifies.
      #
      # @param type [String] Record type
      # @param expected [String] Expected value
      # @param actual_values [Array<String>] Full DNS result set
      # @return [Array(Array<String>, Boolean)] [candidates, ambiguous]
      def select_txt_record_set(type, expected, actual_values)
        return [actual_values, false] unless type == 'TXT'

        discriminator = if RecordNormalizer.dmarc?(expected)
                          RecordNormalizer.method(:dmarc?)
                        elsif RecordNormalizer.spf?(expected)
                          RecordNormalizer.method(:spf?)
                        end
        return [actual_values, false] unless discriminator

        survivors = actual_values.select { |v| discriminator.call(v) }
        [survivors, survivors.size > 1]
      end
    end
  end
end
