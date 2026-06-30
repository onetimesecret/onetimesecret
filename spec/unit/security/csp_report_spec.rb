# spec/unit/security/csp_report_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'json'

require_relative '../../../lib/onetime/security/csp_report'

RSpec.describe Onetime::Security::CspReport do
  SECRET = 'supersecrettoken0123456789abcdef0123456789'

  describe '.redact_url' do
    it 'strips the path entirely so a shallow secret link cannot leak' do
      out = described_class.redact_url("https://host/#{SECRET}")
      expect(out).to eq('https://host/[redacted-path]')
      expect(out).not_to include(SECRET)
    end

    it 'strips the query string and deep path' do
      out = described_class.redact_url("https://host/secret/#{SECRET}?x=y")
      expect(out).to eq('https://host/[redacted-path]')
      expect(out).not_to include(SECRET)
      expect(out).not_to include('x=y')
    end

    it 'keeps a bare origin when there is no path' do
      expect(described_class.redact_url('https://host/')).to eq('https://host/')
    end

    it 'preserves a non-default port' do
      out = described_class.redact_url("https://host:8443/secret/#{SECRET}")
      expect(out).to eq('https://host:8443/[redacted-path]')
    end

    it 'passes CSP keyword sources through unchanged' do
      expect(described_class.redact_url('inline')).to eq('inline')
      expect(described_class.redact_url('eval')).to eq('eval')
      expect(described_class.redact_url('data')).to eq('data')
    end

    it 'refuses to echo an unparseable / schemeless value' do
      expect(described_class.redact_url('::::nonsense')).to eq('[redacted]')
    end

    it 'returns nil for blank input' do
      expect(described_class.redact_url(nil)).to be_nil
      expect(described_class.redact_url('')).to be_nil
    end
  end

  describe '.parse' do
    it 'parses a legacy {"csp-report": {...}} document' do
      body = { 'csp-report' => {
        'document-uri' => "https://host/secret/#{SECRET}",
        'violated-directive' => 'script-src',
      } }.to_json

      summaries = described_class.parse(body, 'application/csp-report')
      expect(summaries.length).to eq(1)
      expect(summaries.first['violated-directive']).to eq('script-src')
      expect(summaries.first['document-uri']).not_to include(SECRET)
    end

    it 'parses a Reporting API array of csp-violation entries' do
      body = [{ 'type' => 'csp-violation', 'body' => {
        'documentURL' => "https://host/secret/#{SECRET}",
        'effectiveDirective' => 'img-src',
      } }].to_json

      summaries = described_class.parse(body, 'application/reports+json')
      expect(summaries.length).to eq(1)
      expect(summaries.first['effective-directive']).to eq('img-src')
      expect(summaries.first['document-uri']).not_to include(SECRET)
    end

    it 'returns [] for an oversized body (never parsed)' do
      big = "{\"pad\":\"#{'x' * (described_class::MAX_BODY_BYTES + 10)}\"}"
      expect(described_class.parse(big, 'application/csp-report')).to eq([])
    end

    it 'returns [] for malformed JSON' do
      expect(described_class.parse('{not json', 'application/csp-report')).to eq([])
    end

    it 'returns [] for nil/empty bodies' do
      expect(described_class.parse(nil, 'application/csp-report')).to eq([])
      expect(described_class.parse('', 'application/csp-report')).to eq([])
    end

    it 'ignores non-csp-violation Reporting API entries' do
      body = [{ 'type' => 'deprecation', 'body' => { 'id' => 'x' } }].to_json
      expect(described_class.parse(body, 'application/reports+json')).to eq([])
    end
  end
end
