# lib/onetime/domain_validation/ascii_hostname.rb
#
# frozen_string_literal: true

require 'simpleidn'

module Onetime
  module DomainValidation
    # Converts display hostnames to the ASCII form used on the DNS wire.
    module AsciiHostname
      MAX_LABEL_BYTES = 63
      MAX_NAME_BYTES  = 253

      class ConversionError < ArgumentError; end

      module_function

      def call(hostname)
        host = hostname.to_s.strip.chomp('.')
        raise ConversionError, 'hostname is blank' if host.empty?
        raise ConversionError, 'hostname is not valid UTF-8' unless host.valid_encoding?

        ascii  = SimpleIDN.to_ascii(host.unicode_normalize(:nfc).downcase)
        labels = ascii.split('.', -1)
        return ascii if ascii.ascii_only? &&
                        ascii.bytesize <= MAX_NAME_BYTES &&
                        labels.all? { |label| label.bytesize.between?(1, MAX_LABEL_BYTES) }

        raise ConversionError, "#{host.inspect} does not fit the DNS name limits"
      rescue ConversionError
        raise
      rescue StandardError => ex
        raise ConversionError, "#{host.inspect} has no A-label form (#{ex.class}: #{ex.message})"
      end
    end
  end
end
