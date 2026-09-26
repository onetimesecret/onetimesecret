# lib/onetime/domain_validation/txt_resolver.rb
#
# frozen_string_literal: true

require_relative 'dns_stub_resolver'

module Onetime
  module DomainValidation
    # TxtResolver - TXT lookup that reports the DNS response code.
    #
    # The transport, time budget and the reasons for not using Resolv::DNS's
    # own lookup methods are described on DnsStubResolver.
    #
    class TxtResolver < DnsStubResolver
      TXT = Resolv::DNS::Resource::IN::TXT

      # @!attribute rcode  [Integer] DNS response code (Resolv::DNS::RCode)
      # @!attribute values [Array<String>] TXT values, character-strings joined
      #   and stripped; empty unless rcode is NOERROR
      Answer = Data.define(:rcode, :values) do
        include RcodePredicates
      end

      # Looks up the TXT records at +hostname+.
      #
      # Returns as soon as a nameserver gives a definitive reply (NOERROR or
      # NXDOMAIN). Other response codes move on to the next nameserver; if
      # none does better, the last such reply is returned so the caller can
      # see the code.
      #
      # @param hostname [String]
      # @return [Answer]
      # @raise [NoReplyError] no nameserver replied within the time budget
      # @raise [ArgumentError] blank hostname or no nameservers configured
      def lookup(hostname)
        name  = absolute_name(hostname)
        reply = query(name, TXT, monotonic + timeout)

        Answer.new(rcode: reply.rcode, values: txt_values(reply, name))
      end

      private

      # Each record's character-strings are joined, then stripped — the same
      # normalisation the strategies have always applied. Wire data is
      # binary; it is scrubbed to UTF-8 so the values survive to_json.
      def txt_values(reply, name)
        records(reply, name, TXT).map do |data|
          data.strings.join.force_encoding(Encoding::UTF_8).scrub.strip
        end
      end
    end
  end
end
