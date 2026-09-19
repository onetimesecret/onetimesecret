# spec/unit/onetime/domain_validation/txt_resolver_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'socket'
require 'onetime/domain_validation/txt_resolver'

# Exercises the resolver against a DNS server on a loopback socket inside this
# process. Nothing leaves the machine. Running real Resolv::DNS::Message bytes
# over real sockets is what catches a stdlib change in the codec on a Ruby
# upgrade, which a stubbed Message would not.
RSpec.describe Onetime::DomainValidation::TxtResolver do
  txt   = Resolv::DNS::Resource::IN::TXT
  cname = Resolv::DNS::Resource::IN::CNAME
  rcode = Resolv::DNS::RCode

  # Minimal loopback DNS server. The responder block receives the decoded
  # query and the transport (:udp / :tcp) and returns a reply Message, or nil
  # to stay silent.
  let(:server_class) do
    Class.new do
      attr_reader :port, :queries

      def initialize(&responder)
        @responder = responder
        @queries   = []
        @udp       = UDPSocket.new
        @udp.bind('127.0.0.1', 0)
        @port      = @udp.addr[1]
        @tcp       = TCPServer.new('127.0.0.1', @port)
        @threads   = [Thread.new { serve_udp }, Thread.new { serve_tcp }]
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

  let(:hostname) { '_onetime-challenge-abc123.secrets.example.com' }
  let(:servers)  { [] }

  after { servers.each(&:stop) }

  def start_server(&responder)
    server_class.new(&responder).tap { |server| servers << server }
  end

  def resolver_for(*started, timeout: 1, attempt_timeout: 0.2)
    described_class.new(
      nameservers: started.map { |server| ['127.0.0.1', server.port] },
      timeout: timeout,
      attempt_timeout: attempt_timeout,
    )
  end

  describe '#lookup' do
    it 'returns the TXT values on NOERROR' do
      server = start_server { |s, q, _| s.reply_to(q, answers: [[nil, txt.new('challenge-value')]]) }
      answer = resolver_for(server).lookup(hostname)

      expect(answer.rcode_name).to eq('NOERROR')
      expect(answer.values).to eq(['challenge-value'])
      expect(answer).to be_definitive
    end

    it 'joins the character-strings of one record and strips the result' do
      server = start_server do |s, q, _|
        s.reply_to(q, answers: [[nil, txt.new(' first-', 'second ')], [nil, txt.new('other')]])
      end

      expect(resolver_for(server).lookup(hostname).values).to eq(%w[first-second other])
    end

    it 'returns UTF-8 values that survive to_json' do
      server = start_server { |s, q, _| s.reply_to(q, answers: [[nil, txt.new("bad\xFFbyte".b)]]) }
      values = resolver_for(server).lookup(hostname).values

      expect(values.first.encoding).to eq(Encoding::UTF_8)
      expect { values.to_json }.not_to raise_error
    end

    it 'reports NXDOMAIN as a definitive answer with no values' do
      server = start_server { |s, q, _| s.reply_to(q, rcode: rcode::NXDomain) }
      answer = resolver_for(server).lookup(hostname)

      expect(answer).to be_nxdomain
      expect(answer).to be_definitive
      expect(answer.values).to eq([])
    end

    it 'reports NOERROR without TXT data as a definitive answer with no values' do
      server = start_server { |s, q, _| s.reply_to(q) }
      answer = resolver_for(server).lookup(hostname)

      expect(answer.rcode_name).to eq('NOERROR')
      expect(answer).to be_definitive
      expect(answer.values).to eq([])
    end

    it 'queries the absolute name once, without resolv.conf search suffixes' do
      server = start_server { |s, q, _| s.reply_to(q, rcode: rcode::NXDomain) }
      resolver_for(server).lookup(hostname)

      expect(server.queries).to eq([[hostname, :udp]])
    end

    it 'accepts a hostname that already ends in a dot' do
      server = start_server { |s, q, _| s.reply_to(q, answers: [[nil, txt.new('v')]]) }

      expect(resolver_for(server).lookup("#{hostname}.").values).to eq(['v'])
    end

    { 'SERVFAIL' => rcode::ServFail, 'REFUSED' => rcode::Refused }.each do |name, code|
      it "returns a non-definitive answer when every nameserver says #{name}" do
        server = start_server { |s, q, _| s.reply_to(q, rcode: code) }
        answer = resolver_for(server).lookup(hostname)

        expect(answer.rcode_name).to eq(name)
        expect(answer).not_to be_definitive
        expect(answer.values).to eq([])
        expect(server.queries.size).to eq(described_class::ROUNDS)
      end
    end

    it 'moves on to the next nameserver after SERVFAIL' do
      failing = start_server { |s, q, _| s.reply_to(q, rcode: rcode::ServFail) }
      healthy = start_server { |s, q, _| s.reply_to(q, answers: [[nil, txt.new('v')]]) }

      expect(resolver_for(failing, healthy).lookup(hostname).values).to eq(['v'])
    end

    it 'moves on to the next nameserver after a timeout' do
      silent  = start_server { |_s, _q, _| nil }
      healthy = start_server { |s, q, _| s.reply_to(q, rcode: rcode::NXDomain) }

      expect(resolver_for(silent, healthy).lookup(hostname)).to be_nxdomain
    end

    it 'raises NoReplyError within the time budget when nothing replies' do
      server  = start_server { |_s, _q, _| nil }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { resolver_for(server, timeout: 0.3, attempt_timeout: 0.1).lookup(hostname) }
        .to raise_error(described_class::NoReplyError, /No DNS reply/)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    end

    it 'raises NoReplyError when the nameserver port is closed' do
      server = start_server { |_s, _q, _| nil }
      server.stop

      expect { resolver_for(server, timeout: 0.3, attempt_timeout: 0.1).lookup(hostname) }
        .to raise_error(described_class::NoReplyError)
    end

    it 'ignores a reply that carries a different message id' do
      server = start_server do |s, q, _|
        s.reply_to(q, id: (q.id + 1) % 0x10000, answers: [[nil, txt.new('forged')]])
      end

      expect { resolver_for(server, timeout: 0.3, attempt_timeout: 0.1).lookup(hostname) }
        .to raise_error(described_class::NoReplyError)
    end

    it 'follows a CNAME chain in the answer section' do
      target = Resolv::DNS::Name.create('challenges.dns-host.example.')
      server = start_server do |s, q, _|
        s.reply_to(q, answers: [[nil, cname.new(target)], [target, txt.new('delegated')]])
      end

      expect(resolver_for(server).lookup(hostname).values).to eq(['delegated'])
    end

    it 'ignores TXT records owned by another name' do
      other  = Resolv::DNS::Name.create('unrelated.example.')
      server = start_server { |s, q, _| s.reply_to(q, answers: [[other, txt.new('stray')]]) }

      expect(resolver_for(server).lookup(hostname).values).to eq([])
    end

    it 'retries over TCP when the UDP reply is truncated' do
      server = start_server do |s, q, transport|
        if transport == :udp
          s.reply_to(q, tc: 1)
        else
          s.reply_to(q, answers: [[nil, txt.new('over-tcp')]])
        end
      end

      expect(resolver_for(server).lookup(hostname).values).to eq(['over-tcp'])
      expect(server.queries.map(&:last)).to eq([:udp, :tcp])
    end

    it 'does not read a reply that is still truncated over TCP as "no TXT data"' do
      server = start_server { |s, q, _| s.reply_to(q, tc: 1) }

      expect { resolver_for(server, timeout: 0.5, attempt_timeout: 0.2).lookup(hostname) }
        .to raise_error(described_class::NoReplyError)
    end

    it 'rejects a blank hostname' do
      expect { described_class.new(nameservers: ['127.0.0.1']).lookup(' ') }
        .to raise_error(ArgumentError, /hostname/)
    end

    it 'rejects an empty nameserver list' do
      expect { described_class.new(nameservers: []).lookup(hostname) }
        .to raise_error(ArgumentError, /nameservers/)
    end
  end

  describe '#initialize' do
    it 'defaults to the system nameservers on port 53' do
      allow(Resolv::DNS::Config).to receive(:default_config_hash).and_return({ nameserver: ['192.0.2.53'] })

      expect(described_class.new.nameservers).to eq([['192.0.2.53', 53]])
    end

    it 'tolerates a system with no resolv.conf' do
      allow(Resolv::DNS::Config).to receive(:default_config_hash).and_return({})

      expect(described_class.new.nameservers).to eq([])
    end
  end

  describe '#close' do
    it 'leaves no socket open after a lookup, and is idempotent' do
      server   = start_server { |s, q, _| s.reply_to(q, rcode: rcode::ServFail) }
      resolver = resolver_for(server)
      opened   = []
      allow(UDPSocket).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |sock| opened << sock }
      end

      resolver.lookup(hostname)
      resolver.close
      resolver.close

      expect(opened).not_to be_empty
      expect(opened).to all(be_closed)
    end
  end
end
