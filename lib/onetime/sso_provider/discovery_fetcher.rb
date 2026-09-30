# lib/onetime/sso_provider/discovery_fetcher.rb
#
# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'
require 'timeout'
require_relative '../http/guard'

module Onetime
  module SsoProvider
    # SSRF-safe fetcher for OIDC discovery documents
    # (/.well-known/openid-configuration).
    #
    # Shared by the tenant "Test Connection" endpoint and the install-wide
    # request-phase issuer check. Deliberately narrower than
    # Onetime::Http::SafeFetch (which follows redirects and is shaped for
    # favicons): a discovery document lives at a fixed URL derived from the
    # issuer, so a redirect is reported as an HTTP error, never followed.
    #
    # Egress guarantees:
    #   - HTTPS only.
    #   - The host is resolved and validated ONCE through Onetime::Http::Guard
    #     and every dial is pinned to a validated IP (Net::HTTP#ipaddr=), while
    #     Host, SNI, and certificate verification keep using the hostname. This
    #     closes the validate-then-reresolve DNS-rebinding window.
    #   - Explicit nil proxy: Net::HTTP.new defaults p_addr to :ENV, and a proxy
    #     from http_proxy would re-resolve the hostname and void the pin.
    #   - VERIFY_PEER.
    #   - No redirect following.
    #   - Open/read timeouts plus a total deadline (open + read timeout) over
    #     the whole exchange — connect, status line, headers and body — so a
    #     slow drip anywhere cannot pin the calling thread past it.
    #   - Body size cap enforced on the declared Content-Length AND during the
    #     streamed read.
    #
    # #fetch never raises for network/HTTP/guard outcomes. It returns a
    # Result whose #status the caller maps to its own error vocabulary:
    #
    #   :ok                2xx; #body holds the (capped) body
    #   :not_found         404
    #   :http_error        any other status, including 3xx (not followed)
    #   :too_large         2xx body exceeds max_bytes
    #   :timeout           open/read timeout or total deadline exceeded
    #   :ssl_error         OpenSSL::SSL::SSLError
    #   :connection_failed SocketError (e.g. DNS failure inside Net::HTTP)
    #   :blocked           Guard refused the target (private/internal/no records)
    #   :invalid_url       unparseable URL, non-HTTPS, or missing host
    #   :error             anything else (e.g. ECONNREFUSED on every address)
    #
    # Result#error carries the exception for :blocked/:ssl_error/
    # :connection_failed/:error. Guard::Blocked messages include the resolved
    # IP — callers must not echo them to end users.
    class DiscoveryFetcher
      DEFAULT_OPEN_TIMEOUT = 10
      DEFAULT_READ_TIMEOUT = 10
      DEFAULT_MAX_BYTES    = 256 * 1024
      DEFAULT_USER_AGENT   = 'OneTimeSecret-SSO-Discovery/1.0'

      STATUSES = [
        :ok, :not_found, :http_error, :too_large, :timeout, :ssl_error,
        :connection_failed, :blocked, :invalid_url, :error
      ].freeze

      Result = Data.define(:status, :url, :http_status, :http_message, :content_type, :body, :error) do
        def ok?
          status == :ok
        end
      end

      # Raised internally to abort a streamed read; never escapes #fetch.
      class BodyTooLarge < StandardError; end
      class DeadlineExceeded < Timeout::Error; end

      attr_reader :open_timeout, :read_timeout, :max_bytes, :user_agent

      def initialize(open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
                     max_bytes: DEFAULT_MAX_BYTES, user_agent: DEFAULT_USER_AGENT)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @max_bytes    = max_bytes
        @user_agent   = user_agent
      end

      # Builds the discovery URL for an issuer. The trailing slash is trimmed
      # ONLY to form the well-known path (OIDC Discovery 1.0 section 4); the
      # issuer identifier itself is never normalized — see DiscoveryIssuer.
      def self.discovery_url_for(issuer)
        "#{issuer.to_s.chomp('/')}/.well-known/openid-configuration"
      end

      # @param url [String] absolute HTTPS URL of the discovery document
      # @return [Result]
      def fetch(url)
        uri = parse_https_uri(url)
        return result(:invalid_url, url) unless uri

        perform(uri, url)
      rescue Timeout::Error => ex # Net::OpenTimeout, Net::ReadTimeout, DeadlineExceeded
        result(:timeout, url, error: ex)
      rescue OpenSSL::SSL::SSLError => ex
        result(:ssl_error, url, error: ex)
      rescue SocketError => ex
        result(:connection_failed, url, error: ex)
      rescue Onetime::Http::Guard::Blocked => ex
        result(:blocked, url, error: ex)
      rescue StandardError => ex
        result(:error, url, error: ex)
      end

      private

      def perform(uri, url)
        request               = Net::HTTP::Get.new(uri.request_uri)
        request['Accept']     = 'application/json'
        request['User-Agent'] = user_agent

        Onetime::Http::Guard.try_each_address!(uri.host) do |pinned_ip|
          http              = Net::HTTP.new(uri.host, uri.port, nil)
          http.ipaddr       = pinned_ip
          http.use_ssl      = true
          http.open_timeout = open_timeout
          http.read_timeout = read_timeout
          http.verify_mode  = OpenSSL::SSL::VERIFY_PEER

          request_once(http, request, url)
        end
      end

      # Reads the body inside the request block so the cap applies to the
      # stream. BodyTooLarge and DeadlineExceeded must escape http.request:
      # Net::HTTP closes the socket on an exception, whereas a block that
      # returns normally makes Net::HTTP read the REST of the body itself,
      # unbounded.
      #
      # The deadline wraps the whole exchange, not just the body read.
      # Net::HTTP reads the status line and headers before it yields, each
      # read bounded only by read_timeout, so a check between body chunks
      # cannot stop a server that drips header bytes.
      def request_once(http, request, url)
        status = nil
        fields = nil
        body   = nil

        Timeout.timeout(open_timeout + read_timeout, DeadlineExceeded, 'discovery fetch exceeded total deadline') do
          http.request(request) do |response|
            status = status_for(response)
            fields = {
              http_status: response.code.to_i,
              http_message: response.message,
              content_type: response['Content-Type'],
            }
            # Error bodies are read (and discarded) under the same cap so
            # Net::HTTP never buffers them unbounded.
            body   = read_capped_body(response)
          end
        end

        # Real Net::HTTP always yields; guard against a response-less return.
        return result(:error, url) unless status

        result(status, url, body: (body if status == :ok), **fields)
      rescue BodyTooLarge
        # An oversize error page still reports its HTTP status; only an
        # oversize 2xx is :too_large.
        result(status == :ok ? :too_large : status, url, **fields)
      end

      def status_for(response)
        case response
        when Net::HTTPSuccess  then :ok
        when Net::HTTPNotFound then :not_found
        else :http_error
        end
      end

      def read_capped_body(response)
        declared = response.content_length
        raise BodyTooLarge if declared && declared > max_bytes

        buffer = String.new(encoding: Encoding::BINARY)
        response.read_body do |chunk|
          buffer << chunk
          raise BodyTooLarge if buffer.bytesize > max_bytes
        end
        buffer.force_encoding(Encoding::UTF_8)
      end

      def parse_https_uri(url)
        uri = URI.parse(url.to_s)
        return nil unless uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty?

        uri
      rescue URI::InvalidURIError
        nil
      end

      def result(status, url, http_status: nil, http_message: nil, content_type: nil, body: nil, error: nil)
        Result.new(
          status: status,
          url: url,
          http_status: http_status,
          http_message: http_message,
          content_type: content_type,
          body: body,
          error: error,
        )
      end
    end
  end
end
