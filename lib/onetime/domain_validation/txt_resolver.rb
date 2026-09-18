# lib/onetime/domain_validation/txt_resolver.rb
#
# frozen_string_literal: true

require 'resolv'
require 'securerandom'
require 'socket'

module Onetime
  module DomainValidation
    # TxtResolver - Minimal TXT stub resolver that reports the DNS response code.
    #
    # Why not Resolv::DNS#getresources / #fetch_resource: Resolv::DNS::Config#resolv
    # rescues its own NXDomain and OtherResolvError internally, so NXDOMAIN,
    # SERVFAIL, REFUSED and (by default) a timeout all surface the same way: no
    # exception and no resources. fetch_resource only yields the reply on
    # NOERROR. That is enough to promote a domain but not to tell "the record
    # does not exist" (definitive) apart from "the lookup failed" (no evidence),
    # which TxtVerifier needs. Verified against resolv 0.7.1 / Ruby 3.4.
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
    # All waits are bounded: `timeout` caps the whole lookup across nameservers
    # and retries, `attempt_timeout` caps a single exchange.
    #
    class TxtResolver
      TXT   = Resolv::DNS::Resource::IN::TXT
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

      # @!attribute rcode  [Integer] DNS response code (Resolv::DNS::RCode)
      # @!attribute values [Array<String>] TXT values, character-strings joined
      #   and stripped; empty unless rcode is NOERROR
      Answer = Data.define(:rcode, :values) do
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
      def initialize(nameservers: nil, timeout: DEFAULT_TIMEOUT, attempt_timeout: ATTEMPT_TIMEOUT)
        @nameservers     = normalize_nameservers(nameservers || system_nameservers)
        @timeout         = timeout
        @attempt_timeout = attempt_timeout
        @sockets         = []
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
        name     = absolute_name(hostname)
        deadline = monotonic + timeout
        last     = nil

        raise ArgumentError, 'No DNS nameservers configured' if nameservers.empty?

        nameservers.cycle(ROUNDS) do |host, port|
          remaining = deadline - monotonic
          break unless remaining.positive?

          reply = attempt(host, port, name, [remaining, attempt_timeout].min)
          next if reply.nil?

          last = Answer.new(rcode: reply.rcode, values: txt_values(reply, name))
          return last if last.definitive?
        end

        last || raise(NoReplyError, "No DNS reply for #{name} within #{timeout}s")
      end

      # Closes any socket still open. Safe to call more than once.
      def close
        @sockets.each { |sock| sock.close unless sock.closed? }
        @sockets.clear
        nil
      end

      private

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
        raise ArgumentError, 'TXT lookup requires a hostname' if fqdn.empty?

        Resolv::DNS::Name.create("#{fqdn}.")
      end

      # One nameserver, UDP first and TCP if the reply was truncated.
      #
      # @return [Resolv::DNS::Message, nil] nil when the nameserver gave no usable reply
      def attempt(host, port, name, budget)
        deadline = monotonic + budget
        id       = SecureRandom.random_number(0x10000)
        query    = build_query(id, name)

        reply = udp_exchange(host, port, query, id, name, deadline)
        reply = tcp_exchange(host, port, query, id, name, deadline) if reply.tc == 1
        reply
      rescue *ATTEMPT_ERRORS => ex
        OT.ld "[TxtResolver] No reply from #{host}:#{port} for #{name}: #{ex.class}: #{ex.message}"
        nil
      end

      def build_query(id, name)
        msg    = Resolv::DNS::Message.new(id)
        msg.rd = 1
        msg.add_question(name, TXT)
        msg.encode
      end

      def udp_exchange(host, port, query, id, name, deadline)
        sock = track(UDPSocket.new(host.include?(':') ? Socket::AF_INET6 : Socket::AF_INET))
        # A connected socket only accepts datagrams from this nameserver, and
        # the kernel picks the (randomised) source port.
        sock.connect(host, port)
        sock.send(query, 0)

        loop do
          wait_readable(sock, deadline)
          reply = decode(sock.recv(UDP_BUFFER_SIZE))
          return reply if reply && answers_query?(reply, id, name)
          # Anything else on this socket is not our reply; keep waiting.
        end
      ensure
        release(sock)
      end

      def tcp_exchange(host, port, query, id, name, deadline)
        remaining = deadline - monotonic
        raise AttemptFailed, 'timed out before TCP retry' unless remaining.positive?

        sock = track(Socket.tcp(host, port, connect_timeout: remaining))
        sock.write([query.bytesize].pack('n') + query)

        length = read_exact(sock, 2, deadline).unpack1('n')
        reply  = decode(read_exact(sock, length, deadline))
        raise AttemptFailed, 'unexpected reply over TCP' unless reply && answers_query?(reply, id, name)
        # A truncated reply decodes with no answer section; read as NOERROR it
        # would pass for "no TXT data".
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
      def answers_query?(reply, id, name)
        return false unless reply.id == id
        return true if reply.tc == 1
        return false unless reply.qr == 1

        question = reply.question.first
        question.nil? || (question[0] == name && question[1] == TXT)
      end

      # TXT values owned by the queried name, following any CNAME chain in the
      # answer section (recursive resolvers return the chain in order). Each
      # record's character-strings are joined, then stripped — the same
      # normalisation the strategies have always applied. Wire data is
      # binary; it is scrubbed to UTF-8 so the values survive to_json.
      def txt_values(reply, name)
        return [] unless reply.rcode == Resolv::DNS::RCode::NoError

        owner = name
        reply.answer.each do |rr_name, _ttl, data|
          owner = data.name if data.is_a?(CNAME) && rr_name == owner
        end

        reply.answer.filter_map do |rr_name, _ttl, data|
          next unless data.is_a?(TXT) && rr_name == owner

          data.strings.join.force_encoding(Encoding::UTF_8).scrub.strip
        end
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
