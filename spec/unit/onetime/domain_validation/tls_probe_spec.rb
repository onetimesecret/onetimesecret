# spec/unit/onetime/domain_validation/tls_probe_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'openssl'
require 'socket'
require 'onetime/domain_validation/tls_probe'

# Hermetic: DNS is a scripted resolver, and the connector seam redirects the
# dial for the vetted public IP to a TLS server on a loopback socket inside
# this process. The handshake, chain and hostname verification are real
# OpenSSL; the trust anchor is a CA generated here and injected as cert_store.
RSpec.describe Onetime::DomainValidation::TlsProbe do
  answer_class = Onetime::DomainValidation::AddressResolver::Answer
  rcode        = Resolv::DNS::RCode

  # Test PKI, built once for the file.
  pki = Module.new do
    module_function

    def key
      OpenSSL::PKey::EC.generate('prime256v1')
    end

    def certificate(subject, key, issuer: nil, issuer_key: nil, ca: false, san: nil)
      cert            = OpenSSL::X509::Certificate.new
      cert.version    = 2
      cert.serial     = OpenSSL::BN.rand(64)
      cert.subject    = OpenSSL::X509::Name.parse(subject)
      cert.issuer     = (issuer || cert).subject
      cert.public_key = key
      cert.not_before = Time.now - 3600
      cert.not_after  = Time.now + 86_400

      ext                     = OpenSSL::X509::ExtensionFactory.new
      ext.subject_certificate = cert
      ext.issuer_certificate  = issuer || cert
      cert.add_extension(ext.create_extension('basicConstraints', ca ? 'CA:TRUE' : 'CA:FALSE', true))
      cert.add_extension(ext.create_extension('subjectAltName', "DNS:#{san}")) if san
      cert.sign(issuer_key || key, OpenSSL::Digest.new('SHA256'))
      cert
    end

    def ca
      @ca ||= begin
        ca_key = key
        [certificate('/CN=TlsProbe Spec CA', ca_key, ca: true), ca_key]
      end
    end

    def leaf(hostname, signer: ca)
      @leaves                    ||= {}
      @leaves[[hostname, signer]] ||= begin
        leaf_key = key
        [certificate("/CN=#{hostname}", leaf_key, issuer: signer[0], issuer_key: signer[1], san: hostname), leaf_key]
      end
    end

    def untrusted_ca
      @untrusted_ca ||= begin
        ca_key = key
        [certificate('/CN=Some Other CA', ca_key, ca: true), ca_key]
      end
    end
  end

  # Loopback TLS server. Records the SNI name and any bytes the client sent
  # after the handshake.
  let(:tls_server_class) do
    Class.new do
      attr_reader :port, :server_names, :received

      def initialize(cert, key)
        @server_names       = []
        @received           = []
        ctx                 = OpenSSL::SSL::SSLContext.new
        ctx.cert            = cert
        ctx.key             = key
        ctx.servername_cb   = lambda { |(_, name)|
          @server_names << name
          nil
        }
        @tcp                = TCPServer.new('127.0.0.1', 0)
        @port               = @tcp.addr[1]
        @ssl                = OpenSSL::SSL::SSLServer.new(@tcp, ctx)
        @thread             = Thread.new { serve }
        @thread.report_on_exception = false
      end

      def stop
        @thread.kill
        @tcp.close unless @tcp.closed?
      end

      private

      def serve
        loop do
          client = @ssl.accept
          @received << client.read
          client.close
        rescue OpenSSL::SSL::SSLError, SystemCallError, EOFError
          next
        end
      end
    end
  end

  let(:hostname)   { 'secrets.example.com' }
  let(:public_ip)  { '93.184.216.34' }
  let(:cert_store) { OpenSSL::X509::Store.new.tap { |store| store.add_cert(pki.ca[0]) } }
  let(:servers)    { [] }
  let(:dialled)    { [] }

  let(:resolver) do
    Class.new do
      attr_accessor :answer, :error
      attr_reader :lookups, :closed

      def initialize
        @lookups = []
        @closed  = 0
      end

      def lookup(hostname)
        @lookups << hostname
        raise error if error

        answer
      end

      def close
        @closed += 1
      end
    end.new
  end

  # Records the address the probe asked for, then dials the loopback server.
  let(:connector) do
    lambda do |ip, port, timeout|
      dialled << [ip, port]
      Socket.tcp('127.0.0.1', servers.last.port, connect_timeout: timeout)
    end
  end

  let(:probe) { described_class.new(resolver_factory: -> { resolver }, connector: connector, cert_store: cert_store) }

  subject(:result) { probe.probe(hostname) }

  before do
    allow(OT).to receive(:lw)
    allow(OT).to receive(:ld)
  end

  after { servers.each(&:stop) }

  # define_method: a closure, so the describe-level locals are visible.
  define_method(:resolves_to) do |*addresses|
    resolver.answer = answer_class.new(rcode: rcode::NoError, addresses: addresses)
  end

  def start_tls_server(cert_and_key)
    tls_server_class.new(*cert_and_key).tap { |server| servers << server }
  end

  context 'with an internationalised hostname' do
    let(:hostname) { 'Bücher.example' }
    let(:a_label)  { 'xn--bcher-kva.example' }

    before do
      resolves_to(public_ip)
      start_tls_server(pki.leaf(a_label))
    end

    it 'resolves, sends SNI and verifies the certificate in the A-label form' do
      expect(result.is_resolving).to be(true)
      expect(result.has_ssl).to be(true)
      expect(resolver.lookups).to eq([a_label])
      expect(servers.last.server_names).to eq([a_label])
    end
  end

  context 'when the name resolves and the server presents a valid certificate' do
    before do
      resolves_to(public_ip)
      start_tls_server(pki.leaf(hostname))
    end

    it 'reports resolving with SSL' do
      expect(result.is_resolving).to be(true)
      expect(result.has_ssl).to be(true)
      expect(result).not_to be_indeterminate
    end

    it 'dials the vetted IP on 443, not the hostname' do
      result

      expect(dialled).to eq([[public_ip, 443]])
      expect(result.connected_to).to eq(public_ip)
    end

    it 'sends the hostname as SNI and returns the certificate' do
      expect(result.certificate.subject.to_s).to eq("/CN=#{hostname}")
      expect(servers.last.server_names).to eq([hostname])
    end

    it 'sends no application data' do
      result
      sleep 0.05 # let the server thread finish its read

      expect(servers.last.received).to eq([''])
    end

    it 'normalises the hostname before looking it up' do
      probe.probe(" #{hostname.upcase}. ")

      expect(resolver.lookups).to eq([hostname])
    end

    it 'closes the resolver' do
      result

      expect(resolver.closed).to eq(1)
    end
  end

  context 'when the certificate is for a different hostname' do
    before do
      resolves_to(public_ip)
      start_tls_server(pki.leaf('other.example.com'))
    end

    it 'reports resolving without SSL' do
      expect(result.is_resolving).to be(true)
      expect(result.has_ssl).to be(false)
      expect(result.certificate).to be_nil
      expect(result.message).to match(/No valid certificate/)
    end
  end

  context 'when the certificate chain is not trusted' do
    before do
      resolves_to(public_ip)
      start_tls_server(pki.leaf(hostname, signer: pki.untrusted_ca))
    end

    it 'reports resolving without SSL' do
      expect([result.is_resolving, result.has_ssl]).to eq([true, false])
    end
  end

  context 'when the handshake fails' do
    before { resolves_to(public_ip) }

    it 'reports no SSL when the server does not speak TLS' do
      plain  = TCPServer.new('127.0.0.1', 0)
      thread = Thread.new do
        client = plain.accept
        client.write("HTTP/1.1 400 Bad Request\r\n\r\n")
        client.close
      end
      probe = described_class.new(
        resolver_factory: -> { resolver },
        connector: ->(_ip, _port, timeout) { Socket.tcp('127.0.0.1', plain.addr[1], connect_timeout: timeout) },
        cert_store: cert_store,
      )

      result = probe.probe(hostname)

      expect([result.is_resolving, result.has_ssl]).to eq([true, false])
    ensure
      thread&.kill
      plain&.close
    end

    it 'reports no SSL when the connection is refused' do
      probe = described_class.new(resolver_factory: -> { resolver }, connector: ->(*) { raise Errno::ECONNREFUSED })

      result = probe.probe(hostname)

      expect([result.is_resolving, result.has_ssl]).to eq([true, false])
    end
  end

  context 'when the name does not resolve' do
    it 'reports not resolving and no SSL on NXDOMAIN, without connecting' do
      resolver.answer = answer_class.new(rcode: rcode::NXDomain, addresses: [])

      expect([result.is_resolving, result.has_ssl]).to eq([false, false])
      expect(result.message).to eq('No A/AAAA records (NXDOMAIN)')
      expect(dialled).to be_empty
    end

    it 'reports not resolving on NOERROR without address records' do
      resolves_to

      expect([result.is_resolving, result.has_ssl]).to eq([false, false])
      expect(dialled).to be_empty
    end
  end

  context 'when the name resolves to a non-public address' do
    {
      'loopback' => ['127.0.0.1'],
      'private' => ['10.0.0.5'],
      'link-local (metadata)' => ['169.254.169.254'],
      'IPv6 loopback' => ['::1'],
      'IPv4-mapped loopback' => ['::ffff:127.0.0.1'],
      'one public and one private address' => ['93.184.216.34', '192.168.1.10'],
    }.each do |label, addresses|
      it "does not connect: #{label}" do
        resolves_to(*addresses)

        expect(result.is_resolving).to be(true)
        expect(result.has_ssl).to be_nil
        expect(result.connected_to).to be_nil
        expect(dialled).to be_empty
      end
    end

    it 'opens no socket with the default connector either' do
      resolves_to('127.0.0.1')
      allow(Socket).to receive(:tcp)

      described_class.new(resolver_factory: -> { resolver }).probe(hostname)

      expect(Socket).not_to have_received(:tcp)
    end
  end

  context 'when the probe cannot tell' do
    it 'is indeterminate on SERVFAIL' do
      resolver.answer = answer_class.new(rcode: rcode::ServFail, addresses: [])

      expect(result).to be_indeterminate
      expect(result.message).to eq('DNS lookup failed (SERVFAIL)')
      expect(dialled).to be_empty
    end

    it 'is indeterminate when no nameserver replies, and still closes the resolver' do
      resolver.error = Onetime::DomainValidation::AddressResolver::NoReplyError.new('No DNS reply')

      expect(result).to be_indeterminate
      expect(resolver.closed).to eq(1)
      expect(OT).to have_received(:lw).with(/Probe of secrets\.example\.com failed: .*NoReplyError/)
    end

    it 'is indeterminate when the resolver cannot be built' do
      probe = described_class.new(resolver_factory: -> { raise ArgumentError, 'No DNS nameservers configured' })

      expect(probe.probe(hostname)).to be_indeterminate
    end

    it 'is indeterminate for a blank hostname or one with no A-label form, without a lookup' do
      expect(probe.probe(' ')).to be_indeterminate
      expect(probe.probe("#{'ü' * 60}.example")).to be_indeterminate
      expect(probe.probe("b\xFFcher.example")).to be_indeterminate
      expect(resolver.lookups).to be_empty
      expect(OT).to have_received(:lw).with(/Not probing/).exactly(3).times
    end

    [Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH, IO::TimeoutError].each do |error|
      it "leaves has_ssl unknown when the connect fails with #{error}" do
        resolves_to(public_ip)
        probe = described_class.new(resolver_factory: -> { resolver }, connector: ->(*) { raise error })

        result = probe.probe(hostname)

        expect(result.is_resolving).to be(true)
        expect(result.has_ssl).to be_nil
      end
    end

    it 'leaves has_ssl unknown when the handshake times out' do
      stub_const("#{described_class}::TLS_TIMEOUT", 0.3)
      resolves_to(public_ip)
      silent  = TCPServer.new('127.0.0.1', 0) # accepts via the backlog, never speaks
      probe   = described_class.new(
        resolver_factory: -> { resolver },
        connector: ->(_ip, _port, timeout) { Socket.tcp('127.0.0.1', silent.addr[1], connect_timeout: timeout) },
      )
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = probe.probe(hostname)

      expect([result.is_resolving, result.has_ssl]).to eq([true, nil])
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
    ensure
      silent&.close
    end

    it 'is indeterminate on an unexpected error' do
      resolves_to(public_ip)
      probe = described_class.new(resolver_factory: -> { resolver }, connector: ->(*) { raise 'boom' })

      expect(probe.probe(hostname)).to be_indeterminate
    end
  end

  context 'with several vetted addresses' do
    let(:second_ip) { '93.184.216.35' }

    before { resolves_to(public_ip, second_ip) }

    it 'tries the next address after a refused connect' do
      start_tls_server(pki.leaf(hostname))
      attempts = []
      probe    = described_class.new(
        resolver_factory: -> { resolver },
        cert_store: cert_store,
        connector: lambda do |ip, _port, timeout|
          attempts << ip
          raise Errno::ECONNREFUSED if ip == public_ip

          Socket.tcp('127.0.0.1', servers.last.port, connect_timeout: timeout)
        end,
      )

      result = probe.probe(hostname)

      expect(attempts).to eq([public_ip, second_ip])
      expect(result.has_ssl).to be(true)
      expect(result.connected_to).to eq(second_ip)
    end

    it 'does not try the next address after a timeout' do
      attempts = []
      probe    = described_class.new(
        resolver_factory: -> { resolver },
        connector: lambda do |ip, *|
          attempts << ip
          raise Errno::ETIMEDOUT
        end,
      )

      expect(probe.probe(hostname).has_ssl).to be_nil
      expect(attempts).to eq([public_ip])
    end

    it 'treats a refusal as the answer when the other address is unroutable' do
      probe = described_class.new(
        resolver_factory: -> { resolver },
        connector: ->(ip, *) { raise(ip == public_ip ? Errno::ECONNREFUSED : Errno::EHOSTUNREACH) },
      )

      expect(probe.probe(hostname).has_ssl).to be(false)
    end
  end
end
