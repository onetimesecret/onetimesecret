# lib/onetime/domain_validation/record_normalizer.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    # RecordNormalizer - semantic comparison of DNS TXT records that follow
    # the tag=value list grammar shared by DKIM (RFC 6376 Section 3.2) and
    # DMARC (RFC 7489 Section 6.4):
    #
    #   tag-list  =  tag-spec *( ";" tag-spec ) [ ";" ]
    #   tag-spec  =  [FWS] tag-name [FWS] "=" [FWS] tag-value [FWS]
    #
    # Raw string comparison fails on semantically equivalent records: the
    # published "v=DMARC1; p=none;" and the expected "v=DMARC1;p=none" parse
    # to the same tag list (issue #4023). This module parses both sides and
    # compares tags instead of bytes.
    #
    # Matching is SUBSET, not equality: every expected tag must be present in
    # the published record. Customer-added tags (e.g. rua=mailto:...) never
    # cause a mismatch, and unrecognized tags are ignored per RFC 6376.
    #
    # Deliberate divergence from RFC 6376: tag NAMES are folded to lowercase
    # even though the RFC declares them case-sensitive. No provider or DNS UI
    # honors that, and folding errs toward verifying a working configuration.
    #
    module RecordNormalizer
      extend self

      # tag-name = ALPHA 0*ALNUMPUNC (ALNUMPUNC = ALPHA / DIGIT / "_").
      # WSP around the name, the "=", and the value is not part of the value;
      # WSP inside the value is significant and preserved.
      TAG_SPEC = /\A\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.*?)\s*\z/m

      # RFC 7489 Section 6.6.3: DMARC record discovery keeps records whose
      # first tag is v=DMARC1; everything else is discarded. Lenient on WSP
      # per the tag-spec grammar.
      DMARC_DISCRIMINATOR = /\A\s*v\s*=\s*DMARC1\s*(?:;|\z)/i

      # RFC 6376 Section 3.6.1: DKIM key records carry v=DKIM1 as first tag.
      DKIM_DISCRIMINATOR = /\A\s*v\s*=\s*DKIM1\s*(?:;|\z)/i

      # RFC 7208 Section 4.5: the SPF version section is exactly "v=spf1"
      # followed by a space or the end of the record. SPF is NOT a tag-list;
      # it only gets a discriminator here for record-set selection.
      SPF_DISCRIMINATOR = /\A\s*v=spf1(?:\s|\z)/i

      # DMARC policy tags where presence of the tag satisfies the
      # expectation regardless of value: a customer publishing p=reject
      # against our expected p=none has hardened their policy, not broken it.
      DMARC_POLICY_TAGS = %w[p sp].freeze

      # DKIM tags whose values compare case-insensitively (key type, hash
      # algorithms, service type). Everything else in a DKIM record defaults
      # to case-sensitive per RFC 6376 Section 3.2.
      DKIM_CASE_INSENSITIVE_TAGS = %w[k h s].freeze

      def dmarc?(value)
        DMARC_DISCRIMINATOR.match?(value.to_s)
      end

      def dkim?(value)
        DKIM_DISCRIMINATOR.match?(value.to_s)
      end

      def spf?(value)
        SPF_DISCRIMINATOR.match?(value.to_s)
      end

      # True when the value should be compared as a tag-list (DMARC or DKIM).
      def tag_list?(value)
        dmarc?(value) || dkim?(value)
      end

      # Parse a tag-list into { tag_name => tag_value }.
      #
      # Tag names fold to lowercase; values keep their case and internal
      # whitespace (trimmed at the edges). A single trailing ";" is allowed
      # by the grammar; empty tag-specs elsewhere are not.
      #
      # @param value [String] Raw TXT record value
      # @return [Hash<String, String>, nil] nil when the record is not a
      #   valid tag-list, including when a tag name repeats (RFC 6376:
      #   "if a tag name does occur more than once, the entire tag-list
      #   is invalid")
      def parse(value)
        segments = value.to_s.split(';', -1)
        segments.pop if segments.size > 1 && segments.last.strip.empty?

        tags = {}
        segments.each do |segment|
          match = TAG_SPEC.match(segment)
          return nil unless match

          name = match[1].downcase
          return nil if tags.key?(name)

          tags[name] = match[2]
        end
        tags.empty? ? nil : tags
      end

      # Does the published record satisfy every tag the expected record
      # requires? Returns false when either side fails to parse — an invalid
      # published record (e.g. duplicate tags) never verifies.
      #
      # @param expected [String] The record we told the customer to publish
      # @param published [String] A record found in DNS
      # @return [Boolean]
      def subset_match?(expected, published)
        expected_tags  = parse(expected)
        published_tags = parse(published)
        return false if expected_tags.nil? || published_tags.nil?

        kind = record_kind(expected_tags)

        expected_tags.all? do |name, expected_value|
          published_tags.key?(name) &&
            tag_satisfied?(kind, name, expected_value, published_tags[name])
        end
      end

      # @param tags [Hash<String, String>] Parsed tag-list
      # @return [Symbol] :dmarc, :dkim, or :unknown
      def record_kind(tags)
        case tags['v'].to_s
        when /\ADMARC1\z/i then :dmarc
        when /\ADKIM1\z/i  then :dkim
        else :unknown
        end
      end

      # Per-tag comparison policy. RFC 6376 Section 3.2: "Values MUST be
      # processed as case sensitive unless the specific tag description of
      # semantics specifies case insensitivity."
      def tag_satisfied?(kind, name, expected, published)
        return expected.casecmp?(published) if name == 'v'

        case kind
        when :dmarc
          return true if DMARC_POLICY_TAGS.include?(name)

          # Remaining DMARC values are ABNF keywords (case-insensitive per
          # RFC 5234 Section 2.3), URIs, or domain names (RFC 4343).
          expected.casecmp?(published)
        when :dkim
          if name == 'p'
            # Base64 key data is case-sensitive, but DNS UIs wrap long keys,
            # so internal whitespace is not significant.
            strip_wsp(expected) == strip_wsp(published)
          elsif DKIM_CASE_INSENSITIVE_TAGS.include?(name)
            expected.casecmp?(published)
          else
            expected == published
          end
        else
          expected == published
        end
      end

      def strip_wsp(value)
        value.gsub(/\s+/, '')
      end
    end
  end
end
