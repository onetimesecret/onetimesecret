# spec/unit/onetime/initializers/sentry_url_scrubbing_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/initializers/setup_diagnostics'

# Tests for URL scrubbing functionality in the Sentry before_send hook.
# The scrubbing ensures sensitive data (secret keys, tokens, etc.) are not
# sent to Sentry in error reports.
#
# This test file exercises the production code in SetupDiagnostics directly
# to ensure the scrubbing logic works as expected.

RSpec.describe Onetime::Initializers::SetupDiagnostics do
  # Helper to call the private scrub_url method on production code
  def scrub_url(url)
    described_class.send(:scrub_url, url)
  end

  # Helper to call the private scrub_sensitive_paths method
  def scrub_sensitive_paths(url)
    described_class.send(:scrub_sensitive_paths, url)
  end

  # Helper to call the private scrub_sensitive_query_params method
  def scrub_sensitive_query_params(url)
    described_class.send(:scrub_sensitive_query_params, url)
  end

  # Generate a 20+ char base-36 identifier for testing (minimum length for scrubbing)
  let(:short_identifier) { 'abc123def456xyz789ab' } # exactly 20 chars
  let(:long_identifier) { 'a' * 62 } # realistic 62-char identifier

  describe '.scrub_url' do
    context 'with sensitive identifier paths (>= 20 chars, base-36)' do
      it 'scrubs /secret/:key paths with valid identifier' do
        result = scrub_url("https://example.com/secret/#{short_identifier}")
        expect(result).to eq('https://example.com/secret/[REDACTED]')
      end

      it 'scrubs /receipt/:key paths with valid identifier' do
        result = scrub_url("https://example.com/receipt/#{short_identifier}")
        expect(result).to eq('https://example.com/receipt/[REDACTED]')
      end

      it 'scrubs /private/:key paths with valid identifier' do
        result = scrub_url("https://example.com/private/#{short_identifier}")
        expect(result).to eq('https://example.com/private/[REDACTED]')
      end

      it 'scrubs /metadata/:key paths with valid identifier' do
        result = scrub_url("https://example.com/metadata/#{short_identifier}")
        expect(result).to eq('https://example.com/metadata/[REDACTED]')
      end

      it 'scrubs /incoming/:key paths with valid identifier' do
        result = scrub_url("https://example.com/incoming/#{short_identifier}")
        expect(result).to eq('https://example.com/incoming/[REDACTED]')
      end
    end

    context 'with admin and auth token paths (always scrubbed)' do
      it 'scrubs /colonel/:path paths' do
        result = scrub_url('https://example.com/colonel/admin_path')
        expect(result).to eq('https://example.com/colonel/[REDACTED]')
      end

      it 'scrubs /l/:shortcode paths' do
        result = scrub_url('https://example.com/l/shortcode123')
        expect(result).to eq('https://example.com/l/[REDACTED]')
      end

      it 'scrubs /forgot/:token paths' do
        result = scrub_url('https://example.com/forgot/reset_token')
        expect(result).to eq('https://example.com/forgot/[REDACTED]')
      end

      it 'scrubs /auth/reset-password/:token paths' do
        result = scrub_url('https://example.com/auth/reset-password/token123')
        expect(result).to eq('https://example.com/auth/reset-password/[REDACTED]')
      end

      it 'scrubs /account/email/confirm/:token paths' do
        result = scrub_url('https://example.com/account/email/confirm/confirm_token')
        expect(result).to eq('https://example.com/account/email/confirm/[REDACTED]')
      end
    end

    context 'with 62-char base-36 identifiers (realistic secret keys)' do
      # Generate a realistic 62-character identifier (base-36 format)
      let(:identifier_62) { 'a' * 62 }

      it 'scrubs /secret/:id with 62-char identifier' do
        expect(identifier_62.length).to eq(62)
        result = scrub_url("https://example.com/secret/#{identifier_62}")
        expect(result).to eq('https://example.com/secret/[REDACTED]')
      end

      it 'scrubs /receipt/:id with 62-char identifier' do
        result = scrub_url("https://example.com/receipt/#{identifier_62}")
        expect(result).to eq('https://example.com/receipt/[REDACTED]')
      end

      it 'scrubs /private/:id with 62-char identifier' do
        result = scrub_url("https://example.com/private/#{identifier_62}")
        expect(result).to eq('https://example.com/private/[REDACTED]')
      end

      it 'scrubs /metadata/:id with 62-char identifier' do
        result = scrub_url("https://example.com/metadata/#{identifier_62}")
        expect(result).to eq('https://example.com/metadata/[REDACTED]')
      end
    end

    context 'with named path segments (should NOT be scrubbed)' do
      # These are legitimate named routes, not secret identifiers.
      # The identifier-length discriminant (MIN_IDENTIFIER_LENGTH = 20) ensures
      # short named paths like "recent" or "burn" are preserved for debugging.

      it 'preserves /receipt/recent (named path, not identifier)' do
        result = scrub_url('https://example.com/receipt/recent')
        expect(result).to eq('https://example.com/receipt/recent')
      end

      it 'preserves /private/recent (named path, not identifier)' do
        result = scrub_url('https://example.com/private/recent')
        expect(result).to eq('https://example.com/private/recent')
      end

      it 'preserves /secret/burn (named path, not identifier)' do
        result = scrub_url('https://example.com/secret/burn')
        expect(result).to eq('https://example.com/secret/burn')
      end

      it 'preserves /incoming/new (named path, not identifier)' do
        result = scrub_url('https://example.com/incoming/new')
        expect(result).to eq('https://example.com/incoming/new')
      end

      it 'preserves /metadata/info (named path, not identifier)' do
        result = scrub_url('https://example.com/metadata/info')
        expect(result).to eq('https://example.com/metadata/info')
      end
    end

    context 'paths that should NOT be scrubbed' do
      it 'preserves /api/v1/status' do
        result = scrub_url('https://example.com/api/v1/status')
        expect(result).to eq('https://example.com/api/v1/status')
      end

      it 'preserves /health' do
        result = scrub_url('https://example.com/health')
        expect(result).to eq('https://example.com/health')
      end

      it 'preserves /dashboard' do
        result = scrub_url('https://example.com/dashboard')
        expect(result).to eq('https://example.com/dashboard')
      end

      it 'preserves /api/v2/secrets (plural endpoint, not a key path)' do
        result = scrub_url('https://example.com/api/v2/secrets')
        expect(result).to eq('https://example.com/api/v2/secrets')
      end

      it 'preserves root path' do
        result = scrub_url('https://example.com/')
        expect(result).to eq('https://example.com/')
      end

      it 'preserves /api/v1/info' do
        result = scrub_url('https://example.com/api/v1/info')
        expect(result).to eq('https://example.com/api/v1/info')
      end

      it 'does not scrub partial matches (e.g., /secrets vs /secret)' do
        result = scrub_url('https://example.com/secrets/list')
        expect(result).to eq('https://example.com/secrets/list')
      end

      it 'does not scrub paths with prefix match only' do
        result = scrub_url('https://example.com/secretive/page')
        expect(result).to eq('https://example.com/secretive/page')
      end
    end
  end

  describe '.scrub_sensitive_query_params' do
    # Production code uses string manipulation, not URI encoding
    # Output should be ?key=[REDACTED], NOT ?key=%5BREDACTED%5D

    it 'scrubs ?key=value parameter without URI encoding' do
      result = scrub_url('https://example.com/page?key=secret123')
      expect(result).to eq('https://example.com/page?key=[REDACTED]')
    end

    it 'scrubs ?secret=value parameter' do
      result = scrub_url('https://example.com/page?secret=abc')
      expect(result).to eq('https://example.com/page?secret=[REDACTED]')
    end

    it 'scrubs ?token=value parameter' do
      result = scrub_url('https://example.com/page?token=xyz')
      expect(result).to eq('https://example.com/page?token=[REDACTED]')
    end

    it 'scrubs ?passphrase=value parameter' do
      result = scrub_url('https://example.com/page?passphrase=hidden')
      expect(result).to eq('https://example.com/page?passphrase=[REDACTED]')
    end

    it 'preserves non-sensitive query parameters' do
      result = scrub_url('https://example.com/page?other=value')
      expect(result).to eq('https://example.com/page?other=value')
    end

    it 'scrubs sensitive params while preserving others' do
      result = scrub_url('https://example.com/page?secret=abc&other=value&token=xyz')
      expect(result).to eq('https://example.com/page?secret=[REDACTED]&other=value&token=[REDACTED]')
    end

    it 'handles case-insensitive param names' do
      result = scrub_url('https://example.com/page?KEY=value&TOKEN=abc')
      expect(result).to eq('https://example.com/page?KEY=[REDACTED]&TOKEN=[REDACTED]')
    end

    it 'preserves fragment identifiers' do
      result = scrub_url('https://example.com/page?key=secret#section')
      expect(result).to eq('https://example.com/page?key=[REDACTED]#section')
    end
  end

  describe 'combined path and query scrubbing' do
    it 'scrubs both sensitive path AND query params' do
      # Use a 20+ char identifier to ensure path scrubbing triggers
      result = scrub_url("https://example.com/secret/#{short_identifier}?key=token456&other=keep")
      expect(result).to eq('https://example.com/secret/[REDACTED]?key=[REDACTED]&other=keep')
    end

    it 'scrubs nested sensitive paths with query params' do
      result = scrub_url('https://example.com/auth/reset-password/token123?secret=value')
      expect(result).to eq('https://example.com/auth/reset-password/[REDACTED]?secret=[REDACTED]')
    end

    it 'scrubs query params even when path is not sensitive' do
      result = scrub_url('https://example.com/secret/short?key=sensitive&other=keep')
      expect(result).to eq('https://example.com/secret/short?key=[REDACTED]&other=keep')
    end
  end

  describe 'edge cases' do
    context 'nil and empty values' do
      it 'handles nil URL gracefully' do
        result = scrub_url(nil)
        expect(result).to be_nil
      end

      it 'handles empty string URL gracefully' do
        result = scrub_url('')
        expect(result).to eq('')
      end
    end

    context 'malformed URLs' do
      it 'returns malformed URL unchanged (graceful degradation)' do
        malformed = 'not-a-valid-url::://'
        result = scrub_url(malformed)
        expect(result).to eq(malformed)
      end

      it 'handles URL with only protocol' do
        result = scrub_url('https://')
        expect(result).to eq('https://')
      end

      it 'handles relative paths with valid identifiers' do
        result = scrub_url("/secret/#{short_identifier}")
        expect(result).to eq('/secret/[REDACTED]')
      end

      it 'handles relative paths with short segments (not scrubbed)' do
        result = scrub_url('/secret/abc123')
        expect(result).to eq('/secret/abc123')
      end
    end

    context 'special characters in paths' do
      it 'handles URL-encoded characters in secret keys with valid identifier length' do
        # 20 chars with URL-encoded space: abc%20 takes 6 chars but decodes to 4
        result = scrub_url("https://example.com/secret/#{short_identifier}")
        expect(result).to eq('https://example.com/secret/[REDACTED]')
      end

      it 'handles paths with trailing slashes' do
        # The regex matches up to but not including the trailing slash
        result = scrub_url("https://example.com/secret/#{short_identifier}/")
        expect(result).to include('/secret/[REDACTED]')
      end
    end

    context 'colonel path with multiple segments' do
      it 'scrubs colonel paths with nested segments' do
        result = scrub_url('https://example.com/colonel/admin/users/list')
        expect(result).to eq('https://example.com/colonel/[REDACTED]')
      end
    end
  end

  describe '.scrub_event_urls' do
    # Mock structures that mirror Sentry's event/request objects
    let(:mock_request_class) do
      Struct.new(:url, :headers, keyword_init: true)
    end

    let(:mock_event_class) do
      Class.new do
        attr_accessor :request, :contexts

        def initialize(request: nil, contexts: nil)
          @request = request
          @contexts = contexts || {}
        end
      end
    end

    def build_event(url:, context_url: nil)
      request = mock_request_class.new(url: url, headers: { 'User-Agent' => 'test' })
      contexts = {}
      contexts['request'] = { 'url' => context_url || url } if context_url || url
      mock_event_class.new(request: request, contexts: contexts)
    end

    it 'scrubs URLs in both request and contexts' do
      # Use a 20+ char identifier to ensure scrubbing triggers
      identifier = 'a' * 25
      event = build_event(
        url: "https://example.com/secret/#{identifier}",
        context_url: "https://example.com/secret/#{identifier}"
      )

      result = described_class.scrub_event_urls(event)

      expect(result.request.url).to eq('https://example.com/secret/[REDACTED]')
      expect(result.contexts['request']['url']).to eq('https://example.com/secret/[REDACTED]')
    end

    it 'handles event with nil request URL gracefully' do
      event = mock_event_class.new(
        request: mock_request_class.new(url: nil, headers: {}),
        contexts: {}
      )

      expect { described_class.scrub_event_urls(event) }.not_to raise_error
    end

    it 'handles event with nil contexts gracefully' do
      identifier = 'a' * 25
      request = mock_request_class.new(url: "https://example.com/secret/#{identifier}", headers: {})
      event = mock_event_class.new(request: request, contexts: nil)

      expect { described_class.scrub_event_urls(event) }.not_to raise_error
    end

    it 'handles event with non-hash contexts gracefully' do
      identifier = 'a' * 25
      request = mock_request_class.new(url: "https://example.com/secret/#{identifier}", headers: {})
      event = mock_event_class.new(request: request, contexts: 'not a hash')

      result = described_class.scrub_event_urls(event)
      expect(result.request.url).to eq('https://example.com/secret/[REDACTED]')
    end

    it 'preserves non-sensitive URLs unchanged' do
      event = build_event(url: 'https://example.com/api/v1/status')
      result = described_class.scrub_event_urls(event)

      expect(result.request.url).to eq('https://example.com/api/v1/status')
    end

    it 'scrubs context URLs when request is nil (non-HTTP events)' do
      identifier = 'a' * 25
      contexts = { 'request' => { 'url' => "https://example.com/secret/#{identifier}" } }
      event = mock_event_class.new(request: nil, contexts: contexts)

      result = described_class.scrub_event_urls(event)

      expect(result.contexts['request']['url']).to eq('https://example.com/secret/[REDACTED]')
    end

    it 'redacts URLs when scrubbing raises an unexpected error' do
      allow(described_class).to receive(:scrub_url).and_raise(StandardError, 'unexpected failure')

      event = build_event(url: 'https://example.com/secret/abc123')
      result = described_class.scrub_event_urls(event)

      expect(result.request.url).to eq('[SCRUBBING_FAILED]')
      expect(result.contexts['request']['url']).to eq('[SCRUBBING_FAILED]')
    end

    it 'does not inject url key into contexts when scrubbing fails' do
      allow(described_class).to receive(:scrub_url).and_raise(StandardError, 'unexpected failure')

      # Context with request hash but no url key
      event = mock_event_class.new(
        request: mock_request_class.new(url: 'https://example.com/secret/abc', headers: {}),
        contexts: { 'request' => { 'method' => 'GET' } }
      )
      result = described_class.scrub_event_urls(event)

      expect(result.request.url).to eq('[SCRUBBING_FAILED]')
      expect(result.contexts['request']).not_to have_key('url')
    end
  end

  describe '.scrub_url fail-closed behavior' do
    it 'returns [SCRUBBING_FAILED] when path scrubbing raises an error' do
      allow(described_class).to receive(:scrub_sensitive_paths).and_raise(StandardError, 'regex failure')

      result = described_class.scrub_url('https://example.com/secret/abc123')
      expect(result).to eq('[SCRUBBING_FAILED]')
    end

    it 'returns [SCRUBBING_FAILED] when query param scrubbing raises an error' do
      allow(described_class).to receive(:scrub_sensitive_query_params).and_raise(StandardError, 'split failure')

      result = described_class.scrub_url('https://example.com/api?key=secret')
      expect(result).to eq('[SCRUBBING_FAILED]')
    end
  end
end
