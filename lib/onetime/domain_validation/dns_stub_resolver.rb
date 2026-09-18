# lib/onetime/domain_validation/dns_stub_resolver.rb
#
# frozen_string_literal: true

require 'resolv'
require 'securerandom'
require 'socket'

module Onetime
  module DomainValidation
    # DnsStubResolver - Minimal stub resolver that reports the DNS response code.
    #
    # Why not Resolv::DNS#getresources / #getaddresses / #fetch_resource:
    # Resolv::DNS::Config#resolv rescues its own NXDomain and OtherResolvError
    # internally, so NXDOMAIN, SERVFAIL, REFUSED and (by default) a timeout all
    # surface the same way: no exception and no resources. fetch_resource only
    # yields the reply on NOERROR. That is enough to promote a domain but not
    # to tell "the record does not exist" (definitive) apart from "the lookup
    # failed" (no evidence), which the domain checks need. Verified against
    # resolv 0.7.1 / Ruby 3.4.
    #
    # This class therefore sends the query itself and uses only the
    # Resolv::DNS::Message codec (the same object fetch_resource yields). It
    # asks the system's recursive resolvers (/etc/resolv.conf) with RD set, over
    # UDP, retrying over TCP when the reply is truncated.
    #
    # The query name is always absolute. Resolv applies the resolv.conf search
    # list to relative names, so an NXDOMAIN for "_challenge.example.com" is
    # retried as "_challenge.example.com.<search domain>", where a wildcard in
    # the search domain could answer for the customer's zone.
    #
    # All waits are bounded: `timeout` caps a whole lookup across nameservers
    # and retries, `attempt_timeout` caps a single exchange.
    #
    # Subclasses (TxtResolver, AddressResolver) add the record-type-specific
    # #lookup on top of #query and #records.
    #
    class DnsStubResolver
      CNAME = Resolv::DNS::Resource::IN::CNAME

      DNS_PORT        = 53
      UDP_BUFFER_SIZE = 4096
      DEFAULT_TIMEOUT = 5 # seconds, whole lookup
      ATTEMPT_TIMEOUT = 2 # seconds, one exchange with one nameserver
      ROUNDS          = 2 # passes over the nameserver list

      # Response codes that are an answer about the name itself. Everything
      # else (SERVFAIL, REFUSED, ...) describes the resolver's own trouble.
      DEFINITIVE_RCODES = [Resolv::DNS::RCode::NoError, Resolv::DNS::RCode::NXDomain].freeze

      RCODE_NAMES = {
        Resolv::DNS::RCode::NoError => 'NOERROR',
        Resolv::DNS::RCode::FormErr => 'FORMERR',
        Resolv::DNS::RCode::ServFail => 'SERVFAIL',
        Resolv::DNS::RCode::NXDomain => 'NXDOMAIN',
        Resolv::DNS::RCode::NotImp => 'NOTIMP',
        Resolv::DNS::RCode::Refused => 'REFUSED',
      }.freeze

      # Raised when no nameserver produced a reply within the time budget.
      class NoReplyError < StandardError; end

      # One failed exchange; the next nameserver is tried.
      class AttemptFailed < StandardError; end

      # Socket-level failures that mean "this nameserver did not answer".
      ATTEMPT_ERRORS = [AttemptFailed, SystemCallError, SocketError, IOError].freeze

      # Shared by the subclasses' Answer value objects.
      module RcodePredicates
        def rcode_name
          RCODE_NAMES.fetch(rcode, "RCODE#{rcode}")
        end

        def definitive?
          DEFINITIVE_RCODES.include?(rcode)
        end

        def nxdomain?
          rcode == Resolv::DNS::RCode::NXDomain
        end
      end

      attr_reader :nameservers, :timeout, :attempt_timeout

      # @param nameservers [Array<String, Array(String, Integer)>, nil] Recursive
      #   resolvers to ask; defaults to the nameserver lines of /etc/resolv.conf
      # @param timeout [Numeric] Budget for a whole #lookup, in seconds
      # @param attempt_timeout [Numeric] Budget for one exchange, in seconds
      def initialize(nameservers: nil, timeout: self.class::DEFAULT_TIMEOUT, attempt_timeout: self.class::ATTEMPT_TIMEOUT)
        @nameservers     = normalize_nameservers(nameservers || system_nameservers)
        @timeout         = timeout
        @attempt_timeout = attempt_timeout
        @sockets         = []
      end

      # Closes any socket still open. Safe to call more than once.
      def close
        @sockets.each { |sock| sock.close unless sock.closed? }
        @sockets.clear
        nil
      end

      private

      # Asks each nameserver for +rtype+ records at +name+ until +deadline+.
      #
      # Returns as soon as a nameserver gives a definitive reply (NOERROR or
      # NXDOMAIN, see #ensure_usable!). Other response codes move on to the
      # next nameserver; if none does better, the last such reply is returned
      # so the caller can see the code.
      #
      # @param name [Resolv::DNS::Name] absolute name (see #absolute_name)
      # @param rtype [Class] Resolv::DNS::Resource::IN::*
      # @param deadline [Float] monotonic clock value
      # @return [Resolv::DNS::Message]
      # @raise [NoReplyError] no nameserver replied within the time budget
      # @raise [ArgumentError] no nameservers configured
      def query(name, rtype, deadline)
        raise ArgumentError, 'No DNS nameservers configured' if nameservers.empty?

        last          = nil
        @last_failure = nil
        nameservers.cycle(ROUNDS) do |host, port|
          remaining = deadline - monotonic
          break unless remaining.positive?

          reply = attempt(host, port, name, rtype, [remaining, attempt_timeout].min)
          next if reply.nil?

          last = reply
          return last if DEFINITIVE_RCODES.include?(last.rcode)
        end

        last || raise(NoReplyError, no_reply_message(name))
      end

      # Carries the last failed exchange, so a nameserver that replies but is
      # never usable (see #ensure_usable!) is named in the caller's log line.
      def no_reply_message(name, summary = 'No DNS reply')
        ["#{summary} for #{name} within #{timeout}s", @last_failure].compact.join(': ')
      end

      # Resource data of +rtype+ owned by the queried name, following any
      # CNAME chain in the answer section. Records owned by an unrelated name
      # are ignored.
      #
      # The chain is followed through a map of the whole answer section, not
      # by reading it top to bottom: RFC 1034 does not fix the order of the
      # answer section, and resolvers have returned the final records ahead
      # of the CNAMEs that lead to them. The walk is bounded by the number of
      # records, so a CNAME loop ends it.
      #
      # @return [Array<Resolv::DNS::Resource>] empty unless rcode is NOERROR
      def records(reply, name, rtype)
        return [] unless reply.rcode == Resolv::DNS::RCode::NoError

        aliases = reply.answer.each_with_object({}) do |(rr_name, _ttl, data), map|
          map[rr_name] = data.name if data.is_a?(CNAME)
        end

        owner = name
        reply.answer.size.times do
          target = aliases[owner]
          break if target.nil?

          owner = target
        end

        reply.answer.filter_map do |rr_name, _ttl, data|
          data if data.is_a?(rtype) && rr_name == owner
        end
      end

      # A NOERROR or NXDOMAIN reply is read as a statement about the name, so
      # it has to be one. Two replies carry those codes without saying
      # anything about the name, and reading either as "no such record" would
      # turn a resolver-side condition into a definitive negative for every
      # domain checked through that resolver:
      #
      #   - ra=0 and aa=0: the nameserver neither recursed for us nor is
      #     authoritative. A server that refuses recursion this way (rather
      #     than with REFUSED) sends NOERROR, an empty answer section and an
      #     upward referral in the authority section.
      #   - a non-empty answer section in which nothing is owned by the
      #     queried name, so none of it can be attributed to the question.
      #
      # @raise [AttemptFailed] the next nameserver is tried
      def ensure_usable!(reply, name)
        return unless DEFINITIVE_RCODES.include?(reply.rcode)

        if reply.ra.to_i.zero? && reply.aa.to_i.zero?
          raise AttemptFailed, "#{RCODE_NAMES[reply.rcode]} reply is neither recursive nor authoritative (ra=0, aa=0)"
        end
        return if reply.answer.empty? || reply.answer.any? { |rr_name, _ttl, _data| rr_name == name }

        raise AttemptFailed, 'answer section holds no record for the queried name'
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def system_nameservers
        Array(Resolv::DNS::Config.default_config_hash[:nameserver])
      end

      def normalize_nameservers(list)
        list.map do |entry|
          host, port = Array(entry)
          [host.to_s, (port || DNS_PORT).to_i]
        end
      end

      # The trailing dot makes the name absolute, which keeps resolv.conf's
      # search list and ndots out of the lookup.
      def absolute_name(hostname)
        fqdn = hostname.to_s.strip.chomp('.')
        raise ArgumentError, 'DNS lookup requires a hostname' if fqdn.empty?

        Resolv::DNS::Name.create("#{fqdn}.")
      end

      # One nameserver, UDP first and TCP if the reply was truncated.
      #
      # @return [Resolv::DNS::Message, nil] nil when the nameserver gave no usable reply
      def attempt(host, port, name, rtype, budget)
        deadline = monotonic + budget
        question = [name, rtype]
        id       = SecureRandom.random_number(0x10000)
        packet   = build_query(id, question)

        reply = udp_exchange(host, port, packet, id, question, deadline)
        reply = tcp_exchange(host, port, packet, id, question, deadline) if reply.tc == 1
        ensure_usable!(reply, name)
        reply
      rescue *ATTEMPT_ERRORS => ex
        @last_failure = "#{host}:#{port} #{ex.message}"
        OT.ld "[#{self.class.name.split('::').last}] No reply from #{host}:#{port} for #{name}: #{ex.class}: #{ex.message}"
        nil
      end

      def build_query(id, question)
        msg    = Resolv::DNS::Message.new(id)
        msg.rd = 1
        msg.add_question(*question)
        msg.encode
      end

      def udp_exchange(host, port, packet, id, question, deadline)
        sock = track(UDPSocket.new(host.include?(':') ? Socket::AF_INET6 : Socket::AF_INET))
        # A connected socket only accepts datagrams from this nameserver, and
        # the kernel picks the (randomised) source port.
        sock.connect(host, port)
        sock.send(packet, 0)

        loop do
          wait_readable(sock, deadline)
          reply = decode(sock.recv(UDP_BUFFER_SIZE))
          return reply if reply && answers_query?(reply, id, question)
          # Anything else on this socket is not our reply; keep waiting.
        end
      ensure
        release(sock)
      end

      def tcp_exchange(host, port, packet, id, question, deadline)
        remaining = deadline - monotonic
        raise AttemptFailed, 'timed out before TCP retry' unless remaining.positive?

        sock = track(Socket.tcp(host, port, connect_timeout: remaining))
        sock.write([packet.bytesize].pack('n') + packet)

        length = read_exact(sock, 2, deadline).unpack1('n')
        reply  = decode(read_exact(sock, length, deadline))
        raise AttemptFailed, 'unexpected reply over TCP' unless reply && answers_query?(reply, id, question)
        # A truncated reply decodes with no answer section; read as NOERROR it
        # would pass for "no data".
        raise AttemptFailed, 'reply truncated over TCP' if reply.tc == 1

        reply
      ensure
        release(sock)
      end

      def wait_readable(sock, deadline)
        remaining = deadline - monotonic
        return if remaining.positive? && sock.wait_readable(remaining)

        raise AttemptFailed, 'timed out waiting for reply'
      end

      def read_exact(sock, length, deadline)
        buffer = +''
        while buffer.bytesize < length
          wait_readable(sock, deadline)
          chunk = sock.read_nonblock(length - buffer.bytesize, exception: false)
          next if chunk == :wait_readable
          raise AttemptFailed, 'connection closed mid-reply' if chunk.nil?

          buffer << chunk
        end
        buffer
      end

      def decode(bytes)
        Resolv::DNS::Message.decode(bytes)
      rescue Resolv::DNS::DecodeError
        nil
      end

      # A reply counts only if it is a response carrying our id and, when the
      # question section is echoed, our question. Message.decode stops after
      # id/tc/rcode on a truncated reply, so only the id can be checked there;
      # all a truncated reply does is send us to TCP.
      def answers_query?(reply, id, question)
        return false unless reply.id == id
        return true if reply.tc == 1
        return false unless reply.qr == 1

        echoed = reply.question.first
        echoed.nil? || (echoed[0] == question[0] && echoed[1] == question[1])
      end

      def track(sock)
        @sockets << sock
        sock
      end

      def release(sock)
        return if sock.nil?

        sock.close unless sock.closed?
        @sockets.delete(sock)
      end
    end
  end
end
