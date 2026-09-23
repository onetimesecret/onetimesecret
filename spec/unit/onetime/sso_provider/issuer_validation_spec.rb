# spec/unit/onetime/sso_provider/issuer_validation_spec.rb
#
# frozen_string_literal: true

# Process-wide install-wide OIDC issuer verdicts (#4513): exact comparison,
# per-state TTLs, and the rule that a failed fetch is never a mismatch.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only spec/unit/onetime/sso_provider/issuer_validation_spec.rb

require 'spec_helper'
require 'json'
require_relative '../../../../lib/onetime/sso_provider/issuer_validation'

RSpec.describe Onetime::SsoProvider::IssuerValidation do
  let(:configured) { 'https://idp.example.com' }
  let(:fetcher) { instance_double(Onetime::SsoProvider::DiscoveryFetcher) }
  let(:now) { [1_000.0] }

  def fetch_result(status, body: nil)
    Onetime::SsoProvider::DiscoveryFetcher::Result.new(
      status: status,
      url: 'https://idp.example.com/.well-known/openid-configuration',
      http_status: status == :ok ? 200 : nil,
      http_message: nil,
      content_type: 'application/json',
      body: body,
      error: nil,
    )
  end

  def respond_with_issuer(issuer)
    allow(fetcher).to receive(:fetch).and_return(fetch_result(:ok, body: { issuer: issuer }.to_json))
  end

  def advance(seconds)
    now[0] += seconds
  end

  before do
    described_class.reset!
    allow(described_class).to receive(:monotonic_now) { now[0] }
  end

  after { described_class.reset! }

  describe '.verify' do
    it 'fetches the discovery URL derived from the configured issuer' do
      respond_with_issuer(configured)

      described_class.verify(configured, fetcher: fetcher)

      expect(fetcher).to have_received(:fetch).with('https://idp.example.com/.well-known/openid-configuration')
    end

    it 'verifies an exact match' do
      respond_with_issuer(configured)

      verdict = described_class.verify(configured, fetcher: fetcher)

      expect(verdict).to be_verified
      expect(verdict.detail).to eq(:match)
      expect(verdict.discovered).to eq(configured)
    end

    it 'rejects an issuer that differs only by a trailing slash' do
      respond_with_issuer("#{configured}/")

      verdict = described_class.verify(configured, fetcher: fetcher)

      expect(verdict).to be_rejected
      expect(verdict.detail).to eq(:mismatch)
      expect(verdict.configured).to eq(configured)
      expect(verdict.discovered).to eq("#{configured}/")
    end

    it 'rejects a document with no issuer' do
      allow(fetcher).to receive(:fetch).and_return(fetch_result(:ok, body: '{"authorization_endpoint":"x"}'))

      verdict = described_class.verify(configured, fetcher: fetcher)

      expect(verdict).to be_rejected
      expect(verdict.detail).to eq(:missing_discovered)
      expect(verdict.discovered).to be_nil
    end

    it 'rejects a non-string issuer without exposing it' do
      allow(fetcher).to receive(:fetch).and_return(fetch_result(:ok, body: '{"issuer":{"a":1}}'))

      verdict = described_class.verify(configured, fetcher: fetcher)

      expect(verdict).to be_rejected
      expect(verdict.detail).to eq(:invalid_discovered)
      expect(verdict.discovered).to be_nil
    end

    [:timeout, :connection_failed, :ssl_error, :blocked, :http_error, :not_found, :too_large, :error].each do |status|
      it "reports a #{status} fetch as unknown, never as a mismatch" do
        allow(fetcher).to receive(:fetch).and_return(fetch_result(status))

        verdict = described_class.verify(configured, fetcher: fetcher)

        expect(verdict).to be_unknown
        expect(verdict.detail).to eq(status)
        expect(described_class.rejected?(configured)).to be(false)
      end
    end

    it 'reports an unparseable body as unknown' do
      allow(fetcher).to receive(:fetch).and_return(fetch_result(:ok, body: '<html>maintenance</html>'))

      verdict = described_class.verify(configured, fetcher: fetcher)

      expect(verdict).to be_unknown
      expect(verdict.detail).to eq(:invalid_json)
    end
  end

  describe 'caching' do
    {
      verified: [:match_issuer, described_class::VERIFIED_TTL],
      rejected: [:slash_issuer, described_class::REJECTED_TTL],
      unknown: [:timeout, described_class::UNKNOWN_TTL],
    }.each do |state, (setup, ttl)|
      it "caches a #{state} verdict for #{ttl}s, then probes again" do
        case setup
        when :match_issuer then respond_with_issuer(configured)
        when :slash_issuer then respond_with_issuer("#{configured}/")
        when :timeout then allow(fetcher).to receive(:fetch).and_return(fetch_result(:timeout))
        end

        first = described_class.verify(configured, fetcher: fetcher)
        advance(ttl - 1)
        again = described_class.verify(configured, fetcher: fetcher)

        expect(again).to equal(first)
        expect(fetcher).to have_received(:fetch).once

        advance(1)
        described_class.verify(configured, fetcher: fetcher)

        expect(fetcher).to have_received(:fetch).twice
      end
    end

    it 'recovers once a cached rejection expires and discovery now matches' do
      respond_with_issuer("#{configured}/")
      described_class.verify(configured, fetcher: fetcher)
      expect(described_class.rejected?(configured)).to be(true)

      advance(described_class::REJECTED_TTL)
      respond_with_issuer(configured)

      expect(described_class.rejected?(configured)).to be(false)
      expect(described_class.verify(configured, fetcher: fetcher)).to be_verified
    end

    it 'keys verdicts by the exact configured issuer' do
      respond_with_issuer("#{configured}/")
      described_class.verify(configured, fetcher: fetcher)

      expect(described_class.rejected?(configured)).to be(true)
      expect(described_class.rejected?("#{configured}/")).to be(false)
    end
  end

  describe '.rejected?' do
    it 'performs no I/O when nothing is cached' do
      allow(fetcher).to receive(:fetch)

      expect(described_class.rejected?(configured)).to be(false)
      expect(fetcher).not_to have_received(:fetch)
    end

    it 'answers false for a blank or non-string issuer' do
      expect(described_class.rejected?(nil)).to be(false)
      expect(described_class.rejected?('')).to be(false)
    end
  end

  it 'is safe under concurrent verification' do
    respond_with_issuer("#{configured}/")

    verdicts = Array.new(8) { Thread.new { described_class.verify(configured, fetcher: fetcher) } }.map(&:value)

    expect(verdicts).to all(be_rejected)
    expect(described_class.rejected?(configured)).to be(true)
  end
end
