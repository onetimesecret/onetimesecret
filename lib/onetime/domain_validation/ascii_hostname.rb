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
