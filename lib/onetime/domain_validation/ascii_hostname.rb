# lib/onetime/domain_validation/ascii_hostname.rb
#
# frozen_string_literal: true

require 'simpleidn'

module Onetime
  module DomainValidation
    # AsciiHostname - The form of a hostname that goes on the wire.
    #
    # CustomDomain stores hostnames as the customer typed them, so an
    # internationalised name arrives here as Unicode ("bücher.example"). DNS
    # and TLS carry such a name as A-labels ("xn--bcher-kva.example").
    # Resolv::DNS::Name will encode the raw UTF-8 bytes without complaint,
    # and the query for that name comes back NXDOMAIN: a definitive negative
    # produced by our encoding, not by the customer's DNS. Every lookup and
    # probe in this module therefore converts through here first.
    #
    # A name that cannot be converted raises ConversionError. Callers must
    # treat that as "could not tell" (indeterminate), never as "not found".
    #
    # The mapping is NFC + downcase + punycode (SimpleIDN). That covers what
    # registries accept in practice; it is not the full UTS #46 table.
    #
    module AsciiHostname
      MAX_LABEL_BYTES = 63
      MAX_NAME_BYTES  = 253

      # An ArgumentError, the class the resolvers already document for a
      # hostname they cannot look up.
      class ConversionError < ArgumentError; end

      class << self
        # @param hostname [String] ASCII or Unicode, with or without a trailing dot
        # @return [String] lower-case A-label form, without a trailing dot
        # @raise [ConversionError]
        def call(hostname)
          host = utf8(hostname.to_s).strip.chomp('.')
          raise ConversionError, 'hostname is blank' if host.empty?

          ascii = host.ascii_only? ? host.downcase : to_a_labels(host)
          ensure_encodable!(ascii, host)
          ascii
        end

        # The key to compare a name by when deciding whether two spellings
        # name the same domain (an email-domain allowlist entry against the
        # domain of an asserted address), or nil when it has none.
        #
        # Stricter than call. SimpleIDN applies the UTS #46 mapping, so
        # fullwidth letters ("ｅｘａｍｐｌｅ.com"), U+3002 as a label separator
        # and a soft hyphen all encode to the A-label of a plainer name. A
        # lookup can tolerate that; an allowlist would then admit an address
        # spelled unlike any listed entry. A Unicode label therefore has a key
        # only when its A-label decodes back to its own NFC, lower-case
        # spelling. Labels are judged one at a time, so a name that mixes the
        # forms ("xn--bcher-kva.bücher.de") keys the same as its fully encoded
        # form. An ASCII label is only lower-cased: an A-label is never
        # decoded (decoding is lossy, see CustomDomain.idn_forms), and
        # surrounding space or a trailing dot is kept, so an ASCII name
        # compares exactly as it did byte for byte.
        #
        # @param hostname [String]
        # @return [String, nil] lower-case A-label form
        def comparison_key(hostname)
          host = utf8(hostname.to_s)
          return host.downcase if host.ascii_only?

          labels = host.unicode_normalize(:nfc).downcase.split('.', -1).map do |label|
            label.ascii_only? ? label : exact_a_label(label)
          end
          return nil if labels.any?(&:nil?)

          ascii = labels.join('.')
          ensure_encodable!(ascii, host)
          ascii
        rescue ConversionError
          nil
        end

        private

        # Checked first: String#strip itself raises on invalid bytes.
        def utf8(host)
          host = host.dup.force_encoding(Encoding::UTF_8) if host.encoding == Encoding::BINARY
          return host if host.valid_encoding?

          raise ConversionError, "#{host.inspect} is not valid #{host.encoding}"
        end

        def to_a_labels(host)
          SimpleIDN.to_ascii(host.unicode_normalize(:nfc).downcase)
        rescue StandardError => ex
          raise ConversionError, "#{host.inspect} has no A-label form (#{ex.class}: #{ex.message})"
        end

        # The A-label of one NFC, lower-case Unicode label, or nil when the
        # UTS #46 mapping changed it on the way (it does not decode back to
        # the label as given).
        def exact_a_label(label)
          ascii = SimpleIDN.to_ascii(label)
          ascii if SimpleIDN.to_unicode(ascii) == label
        rescue StandardError
          nil
        end

        def ensure_encodable!(ascii, host)
          labels = ascii.split('.', -1)
          return if ascii.ascii_only? &&
                    ascii.bytesize <= MAX_NAME_BYTES &&
                    labels.all? { |label| label.bytesize.between?(1, MAX_LABEL_BYTES) }

          raise ConversionError, "#{host.inspect} does not fit the DNS name limits as #{ascii.inspect}"
        end
      end
    end
  end
end
