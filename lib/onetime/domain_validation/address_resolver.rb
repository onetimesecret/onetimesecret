# lib/onetime/domain_validation/address_resolver.rb
#
# frozen_string_literal: true

require_relative 'dns_stub_resolver'

module Onetime
  module DomainValidation
    # AddressResolver - A/AAAA lookup that reports the DNS response code.
    #
    # Resolv::DNS#getaddresses returns [] for NXDOMAIN, SERVFAIL and a timeout
    # alike (see DnsStubResolver). TlsProbe needs to tell "this name has no
    # address" (the domain is not resolving) apart from "the lookup failed"
    # (nothing learned), so it resolves through this class instead.
    #
    # Both families share one time budget, shorter than the TXT lookup's: the
    # status probe runs for every domain on every refresh page.
    #
    class AddressResolver < DnsStubResolver
      A    = Resolv::DNS::Resource::IN::A
      AAAA = Resolv::DNS::Resource::IN::AAAA

      DEFAULT_TIMEOUT = 3 # seconds, A and AAAA together
      ATTEMPT_TIMEOUT = 1 # seconds, one exchange with one nameserver

      # @!attribute rcode     [Integer] DNS response code (Resolv::DNS::RCode)
      # @!attribute addresses [Array<String>] IPv4 then IPv6 addresses
      Answer = Data.define(:rcode, :addresses) do
        include RcodePredicates

        # The name has at least one address. True even when only one family
        # answered: an address in hand is evidence the other family's failed
        # lookup cannot take away.
        def resolves?
          addresses.any?
        end
      end

      # Looks up the A and AAAA records at +hostname+.
      #
      #   addresses found                    -> NOERROR with the addresses
      #   NXDOMAIN, or NOERROR for both
      #   families with no address records   -> definitive, no addresses
      #   anything else                      -> the non-definitive rcode, or
      #                                         NoReplyError when nothing replied
      #
      # @param hostname [String]
      # @return [Answer]
      # @raise [NoReplyError] no nameserver replied within the time budget
      # @raise [ArgumentError] blank hostname or no nameservers configured
      def lookup(hostname)
        name     = absolute_name(hostname)
        deadline = monotonic + timeout

        replies = []
        [A, AAAA].each do |rtype|
          reply = query_family(name, rtype, deadline)
          replies << [rtype, reply]
          # NXDOMAIN is about the name, not the record type.
          break if reply&.rcode == Resolv::DNS::RCode::NXDomain
        end

        combine(name, replies)
      end

      private

      # @return [Resolv::DNS::Message, nil] nil when nothing replied
      def query_family(name, rtype, deadline)
        query(name, rtype, deadline)
      rescue NoReplyError
        nil
      end

      def combine(name, replies)
        addresses = replies.flat_map do |rtype, reply|
          reply ? records(reply, name, rtype).map { |data| data.address.to_s } : []
        end
        return Answer.new(rcode: Resolv::DNS::RCode::NoError, addresses: addresses.uniq) if addresses.any?

        answered = replies.filter_map { |_rtype, reply| reply }
        raise NoReplyError, no_reply_message(name) if answered.empty?

        nxdomain = Resolv::DNS::RCode::NXDomain
        return Answer.new(rcode: nxdomain, addresses: []) if answered.any? { |reply| reply.rcode == nxdomain }

        # One family answering "no data" while the other failed is not a
        # definitive "no address": report the failure.
        unsettled = answered.find { |reply| !DEFINITIVE_RCODES.include?(reply.rcode) }
        return Answer.new(rcode: unsettled.rcode, addresses: []) if unsettled
        raise NoReplyError, no_reply_message(name, 'Incomplete DNS reply') if answered.size < replies.size

        Answer.new(rcode: Resolv::DNS::RCode::NoError, addresses: [])
      end
    end
  end
end
