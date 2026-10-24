# spec/unit/onetime/sso_provider/discovery_fetcher_spec.rb
#
# frozen_string_literal: true

# Egress contract for the shared OIDC discovery fetcher: pinned dial through
# Onetime::Http::Guard, nil proxy, VERIFY_PEER, configurable timeouts, no
# redirect following, and a body size cap.
#
# Hermetic: Guard.resolve_addresses (the DNS seam WebMock cannot intercept)
# and Net::HTTP.new are stubbed; no live DNS or network.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only spec/unit/onetime/sso_provider/discovery_fetcher_spec.rb

require 'spec_helper'
require_relative '../../../../lib/onetime/sso_provider/discovery_fetcher'

RSpec.describe Onetime::SsoProvider::DiscoveryFetcher do
  subject(:fetcher) { described_class.new }

  let(:url) { 'https://idp.example.com/.well-known/openid-configuration' }
  let(:http_instance) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http_instance)
    allow(http_instance).to receive(:ipaddr=)
    allow(http_instance).to receive(:use_ssl=)
    allow(http_instance).to receive(:open_timeout=)
    allow(http_instance).to receive(:read_timeout=)
    allow(http_instance).to receive(:verify_mode=)
    allow(http_instance).to receive(:request)
    stub_resolution(['203.0.113.10'])
  end

  def stub_resolution(addresses)
    allow(Onetime::Http::Guard).to receive(:resolve_addresses).and_return(addresses)
  end

  # Builds a real Net::HTTPResponse whose streamed body yields +chunks+.
  def http_response(klass, code, message, chunks: [], headers: {})
    klass.new('1.1', code, message).tap do |response|
      headers.each { |name, value| response[name] = value }
      allow(response).to receive(:read_body) do |&blk|
        chunks.each { |chunk| blk.call(chunk) }
        nil
      end
    end
  end

  # Net::HTTP#request yields the response to the block before the body is
  # read; mirror that so the fetcher's streamed read runs.
  def respond_with(response)
    allow(http_instance).to receive(:request) do |_request, &blk|
      blk&.call(response)
      response
    end
  end

  describe '#fetch' do
    context 'with a 200 response' do
      let(:body) { '{"issuer":"https://idp.example.com"}' }

      before { respond_with(http_response(Net::HTTPOK, '200', 'OK', chunks: [body], headers: { 'Content-Type' => 'application/json' })) }

      it 'returns :ok with the body and content type' do
        result = fetcher.fetch(url)

        expect(result).to be_ok
        expect(result.body).to eq(body)
        expect(result.body.encoding).to eq(Encoding::UTF_8)
        expect(result.http_status).to eq(200)
        expect(result.content_type).to eq('application/json')
      end

      it 'pins the dial to the validated IP with no proxy and VERIFY_PEER' do
        fetcher.fetch(url)

        expect(Net::HTTP).to have_received(:new).with('idp.example.com', 443, nil)
        expect(http_instance).to have_received(:ipaddr=).with('203.0.113.10')
        expect(http_instance).to have_received(:use_ssl=).with(true)
        expect(http_instance).to have_received(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
      end

      it 'uses the default 10s timeouts' do
        fetcher.fetch(url)

        expect(http_instance).to have_received(:open_timeout=).with(10)
        expect(http_instance).to have_received(:read_timeout=).with(10)
      end

      it 'honours configured timeouts' do
        described_class.new(open_timeout: 3, read_timeout: 2).fetch(url)

        expect(http_instance).to have_received(:open_timeout=).with(3)
        expect(http_instance).to have_received(:read_timeout=).with(2)
      end
    end

    # The request line and headers, as handed to Net::HTTP#request.
    context 'with the request it sends' do
      let(:sent) { [] }

      before do
        response = http_response(Net::HTTPOK, '200', 'OK', chunks: ['{}'])
        allow(http_instance).to receive(:request) do |request, &blk|
          sent << request
          blk&.call(response)
          response
        end
      end

      it 'asks for JSON by default (the discovery callers)' do
        fetcher.fetch(url)

        expect(fetcher.accept).to eq('application/json')
        expect(sent.first['Accept']).to eq('application/json')
        expect(sent.first['User-Agent']).to eq('OneTimeSecret-SSO-Discovery/1.0')
      end

      it 'sends a configured Accept header (SAML IdP metadata)' do
        accept = 'application/samlmetadata+xml, application/xml, text/xml'

        described_class.new(accept: accept).fetch(url)

        expect(sent.first['Accept']).to eq(accept)
      end

      # Entra's App Federation Metadata Url carries ?appid=...; the request
      # line must be the URL's path and query exactly as given.
      it 'forwards the path and query unchanged, with no normalization' do
        metadata_url = 'https://login.microsoftonline.com/Contoso.onmicrosoft.com/FederationMetadata/2007-06/' \
                       'FederationMetadata.xml?appid=00000000-1111-2222-3333-444444444444&x=%2F..%2F&y=a+b'

        result = fetcher.fetch(metadata_url)

        expect(result).to be_ok
        expect(sent.first.path).to eq(
          '/Contoso.onmicrosoft.com/FederationMetadata/2007-06/FederationMetadata.xml' \
          '?appid=00000000-1111-2222-3333-444444444444&x=%2F..%2F&y=a+b',
        )
        expect(Net::HTTP).to have_received(:new).with('login.microsoftonline.com', 443, nil)
      end

      it 'does not resolve dot segments in the path' do
        fetcher.fetch('https://idp.example.com/a/../metadata.xml')

        expect(sent.first.path).to eq('/a/../metadata.xml')
      end

      # The parser is the gate for a metadata document, not the media type.
      it 'returns the body whatever Content-Type the server declares' do
        response = http_response(Net::HTTPOK, '200', 'OK', chunks: ['<md/>'],
          headers: { 'Content-Type' => 'application/octet-stream' })
        respond_with(response)

        result = described_class.new(accept: 'application/xml').fetch(url)

        expect(result).to be_ok
        expect(result.body).to eq('<md/>')
        expect(result.content_type).to eq('application/octet-stream')
      end
    end

    context 'with the body size cap' do
      subject(:fetcher) { described_class.new(max_bytes: 16) }

      it 'defaults to 256 KiB' do
        expect(described_class.new.max_bytes).to eq(256 * 1024)
      end

      it 'rejects a declared Content-Length over the cap without reading the body' do
        response = http_response(Net::HTTPOK, '200', 'OK', chunks: ['{}'], headers: { 'Content-Length' => '17' })
        respond_with(response)

        result = fetcher.fetch(url)

        expect(result.status).to eq(:too_large)
        expect(result.body).to be_nil
        expect(response).not_to have_received(:read_body)
      end

      it 'rejects a streamed body that exceeds the cap without a Content-Length' do
        respond_with(http_response(Net::HTTPOK, '200', 'OK', chunks: ['x' * 10, 'y' * 10]))

        result = fetcher.fetch(url)

        expect(result.status).to eq(:too_large)
        expect(result.body).to be_nil
        expect(result.http_status).to eq(200)
      end

      it 'accepts a body exactly at the cap' do
        respond_with(http_response(Net::HTTPOK, '200', 'OK', chunks: ['x' * 16]))

        expect(fetcher.fetch(url)).to be_ok
      end

      it 'still reports the HTTP status of an oversize error page' do
        respond_with(http_response(Net::HTTPNotFound, '404', 'Not Found', chunks: ['x' * 64]))

        expect(fetcher.fetch(url).status).to eq(:not_found)
      end
    end

    context 'with a redirect' do
      before do
        respond_with(http_response(Net::HTTPFound, '302', 'Found',
          headers: { 'Location' => 'https://attacker.example.net/.well-known/openid-configuration' }))
      end

      it 'reports :http_error and never follows the Location' do
        result = fetcher.fetch(url)

        expect(result.status).to eq(:http_error)
        expect(result.http_status).to eq(302)
        expect(result.body).to be_nil
        expect(http_instance).to have_received(:request).once
        expect(Net::HTTP).to have_received(:new).once
      end
    end

    it 'maps 404 to :not_found' do
      respond_with(http_response(Net::HTTPNotFound, '404', 'Not Found'))

      result = fetcher.fetch(url)

      expect(result.status).to eq(:not_found)
      expect(result.http_status).to eq(404)
    end

    it 'maps other statuses to :http_error with the reason phrase' do
      respond_with(http_response(Net::HTTPServiceUnavailable, '503', 'Service Unavailable'))

      result = fetcher.fetch(url)

      expect(result.status).to eq(:http_error)
      expect(result.http_status).to eq(503)
      expect(result.http_message).to eq('Service Unavailable')
    end

    context 'with a blocked target' do
      it 'returns :blocked without connecting' do
        stub_resolution(['10.0.0.5'])

        result = fetcher.fetch(url)

        expect(result.status).to eq(:blocked)
        expect(result.error).to be_a(Onetime::Http::Guard::Blocked)
        expect(Net::HTTP).not_to have_received(:new)
      end

      it 'blocks a mixed public/private RRset wholesale' do
        stub_resolution(['203.0.113.10', '127.0.0.1'])

        expect(fetcher.fetch(url).status).to eq(:blocked)
        expect(Net::HTTP).not_to have_received(:new)
      end
    end

    it 'rejects non-HTTPS URLs without resolving or connecting' do
      result = fetcher.fetch('http://idp.example.com/.well-known/openid-configuration')

      expect(result.status).to eq(:invalid_url)
      expect(Onetime::Http::Guard).not_to have_received(:resolve_addresses)
      expect(Net::HTTP).not_to have_received(:new)
    end

    it 'rejects unparseable URLs' do
      expect(fetcher.fetch('https://idp example.com/').status).to eq(:invalid_url)
    end

    it 'maps open/read timeouts to :timeout' do
      allow(http_instance).to receive(:request).and_raise(Net::OpenTimeout)

      expect(fetcher.fetch(url).status).to eq(:timeout)
    end

    # The total deadline is open + read timeout (0.1s here) over the whole
    # exchange; each stub stalls well past it.
    context 'with the total deadline' do
      subject(:fetcher) { described_class.new(open_timeout: 0.05, read_timeout: 0.05) }

      it 'maps a slow drip in the body to :timeout' do
        response = Net::HTTPOK.new('1.1', '200', 'OK')
        allow(response).to receive(:read_body) do |&blk|
          blk.call('{')
          sleep 2
          blk.call('}')
        end
        respond_with(response)

        expect(fetcher.fetch(url).status).to eq(:timeout)
      end

      it 'maps slow response headers to :timeout' do
        allow(http_instance).to receive(:request) do
          sleep 2
          raise 'unreachable: the deadline fires before the headers arrive'
        end

        result = fetcher.fetch(url)

        expect(result.status).to eq(:timeout)
        expect(result.error).to be_a(described_class::DeadlineExceeded)
      end
    end

    it 'maps TLS failures to :ssl_error' do
      allow(http_instance).to receive(:request).and_raise(OpenSSL::SSL::SSLError, 'certificate verify failed')

      result = fetcher.fetch(url)

      expect(result.status).to eq(:ssl_error)
      expect(result.error.message).to include('certificate verify failed')
    end

    it 'maps SocketError to :connection_failed' do
      allow(http_instance).to receive(:request).and_raise(SocketError, 'getaddrinfo failed')

      expect(fetcher.fetch(url).status).to eq(:connection_failed)
    end

    it 'maps a SystemCallError raised by the dial (EHOSTUNREACH) to :connection_failed, not :error' do
      allow(http_instance).to receive(:request).and_raise(Errno::EHOSTUNREACH)

      result = fetcher.fetch(url)

      expect(result.status).to eq(:connection_failed)
      expect(result.error).to be_a(Errno::EHOSTUNREACH)
    end

    it 'falls back across validated addresses, then reports :connection_failed when all refuse' do
      stub_resolution(['203.0.113.10', '203.0.113.11'])
      allow(http_instance).to receive(:request).and_raise(Errno::ECONNREFUSED)

      result = fetcher.fetch(url)

      expect(result.status).to eq(:connection_failed)
      expect(result.error).to be_a(Errno::ECONNREFUSED)
      expect(http_instance).to have_received(:ipaddr=).with('203.0.113.10').ordered
      expect(http_instance).to have_received(:ipaddr=).with('203.0.113.11').ordered
    end
  end

  describe '.discovery_url_for' do
    it 'appends the well-known path' do
      expect(described_class.discovery_url_for('https://idp.example.com'))
        .to eq('https://idp.example.com/.well-known/openid-configuration')
    end

    it 'trims one trailing slash for the URL only' do
      expect(described_class.discovery_url_for('https://tenant.auth0.com/'))
        .to eq('https://tenant.auth0.com/.well-known/openid-configuration')
    end
  end
end
