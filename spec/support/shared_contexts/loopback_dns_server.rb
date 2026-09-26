# spec/support/shared_contexts/loopback_dns_server.rb
#
# frozen_string_literal: true

require 'resolv'
require 'socket'

# A DNS server on a loopback socket inside the spec process, for the
# DomainValidation resolvers. Nothing leaves the machine. Running real
# Resolv::DNS::Message bytes over real sockets is what catches a stdlib change
# in the codec on a Ruby upgrade, which a stubbed Message would not.
#
#   server = start_server { |s, query, transport| s.reply_to(query, answers: [[nil, data]]) }
#   server.port     # nameserver port on 127.0.0.1
#   server.queries    # [[name, transport], ...]
#   server.questions  # [type class, ...] in the same order
#
# Servers started with start_server are stopped after each example.
RSpec.shared_context 'with a loopback DNS server' do
  # Minimal loopback DNS server. The responder block receives the decoded
  # query and the transport (:udp / :tcp) and returns a reply Message, or nil
  # to stay silent.
  let(:server_class) do
    Class.new do
      attr_reader :port, :queries, :questions

      def initialize(&responder)
        @responder = responder
        @queries   = []
        @questions = []
        @udp, @tcp = bind_pair
        @port      = @udp.addr[1]
        @threads   = [Thread.new { serve_udp }, Thread.new { serve_tcp }]
      end

      # A nameserver answers on one port over both transports, but UDP and
      # TCP ports are separate namespaces: the ephemeral port the kernel
      # hands the UDP socket may already have a TCP listener (another spec,
      # a lingering TIME_WAIT peer). Retry with a fresh port instead of
      # failing the example with EADDRINUSE.
      def bind_pair(attempts: 20)
        attempts.times do
          udp = UDPSocket.new
          udp.bind('127.0.0.1', 0)
          begin
            return [udp, TCPServer.new('127.0.0.1', udp.addr[1])]
          rescue Errno::EADDRINUSE
            udp.close
          end
        end
        raise Errno::EADDRINUSE, 'no loopback port free on both UDP and TCP'
      end

      def stop
        @threads.each(&:kill)
        [@udp, @tcp].each { |sock| sock.close unless sock.closed? }
      end

      def reply_to(query, rcode: 0, answers: [], tc: 0, id: query.id)
        reply       = Resolv::DNS::Message.new(id)
        reply.qr    = 1
        reply.rd    = 1
        reply.ra    = 1
        reply.tc    = tc
        reply.rcode = rcode
        query.question.each { |name, typeclass| reply.add_question(name, typeclass) }
        answers.each { |name, data| reply.add_answer(name || query.question.first[0], 60, data) }
        reply
      end

      private

      def handle(bytes, transport)
        query = Resolv::DNS::Message.decode(bytes)
        @queries << [query.question.first[0].to_s, transport]
        @questions << query.question.first[1]
        @responder.call(self, query, transport)&.encode
      end

      def serve_udp
        loop do
          bytes, from = @udp.recvfrom(4096)
          reply       = handle(bytes, :udp)
          @udp.send(reply, 0, from[3], from[1]) if reply
        end
      end

      def serve_tcp
        loop do
          client = @tcp.accept
          length = client.read(2).unpack1('n')
          reply  = handle(client.read(length), :tcp)
          client.write([reply.bytesize].pack('n') + reply) if reply
          client.close
        end
      end
    end
  end

  let(:servers)  { [] }

  after { servers.each(&:stop) }

  def start_server(&responder)
    server_class.new(&responder).tap { |server| servers << server }
  end
end
