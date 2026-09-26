# spec/unit/onetime/sso_provider/discovery_issuer_spec.rb
#
# frozen_string_literal: true

# Exact-match contract for OIDC discovery issuer validation. Issuer
# identifiers are compared as exact strings — these specs pin that no
# normalization (trailing slash, case, whitespace) ever creeps in.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only spec/unit/onetime/sso_provider/discovery_issuer_spec.rb

require 'spec_helper'
require_relative '../../../../lib/onetime/sso_provider/discovery_issuer'

RSpec.describe Onetime::SsoProvider::DiscoveryIssuer do
  def check(configured, discovered)
    described_class.check(configured: configured, discovered: discovered)
  end

  describe '.check' do
    it 'accepts an exact match' do
      result = check('https://idp.example.com', 'https://idp.example.com')

      expect(result).to be_ok
      expect(result.reason).to eq(:match)
      expect(result.configured).to eq('https://idp.example.com')
      expect(result.discovered).to eq('https://idp.example.com')
    end

    it 'accepts an exact match that includes a trailing slash' do
      expect(check('https://tenant.auth0.com/', 'https://tenant.auth0.com/')).to be_ok
    end

    it 'rejects a discovered issuer with a trailing slash the configured one lacks' do
      result = check('https://idp.example.com', 'https://idp.example.com/')

      expect(result).not_to be_ok
      expect(result).to be_mismatch
      expect(result.reason).to eq(:mismatch)
      expect(result.configured).to eq('https://idp.example.com')
      expect(result.discovered).to eq('https://idp.example.com/')
    end

    it 'rejects a configured issuer with a trailing slash the discovered one lacks' do
      result = check('https://idp.example.com/', 'https://idp.example.com')

      expect(result.reason).to eq(:mismatch)
    end

    it 'rejects a case-only difference' do
      expect(check('https://idp.example.com', 'https://IDP.example.com').reason).to eq(:mismatch)
    end

    it 'rejects surrounding whitespace' do
      expect(check('https://idp.example.com', ' https://idp.example.com').reason).to eq(:mismatch)
    end

    it 'rejects a different path' do
      expect(check('https://idp.example.com/realms/a', 'https://idp.example.com/realms/b').reason).to eq(:mismatch)
    end

    it 'rejects a scheme difference' do
      expect(check('https://idp.example.com', 'http://idp.example.com').reason).to eq(:mismatch)
    end

    it 'rejects an explicit default port' do
      expect(check('https://idp.example.com', 'https://idp.example.com:443').reason).to eq(:mismatch)
    end

    it 'rejects a nil discovered issuer' do
      result = check('https://idp.example.com', nil)

      expect(result).not_to be_ok
      expect(result.reason).to eq(:missing_discovered)
    end

    it 'rejects an empty discovered issuer' do
      expect(check('https://idp.example.com', '').reason).to eq(:missing_discovered)
    end

    it 'rejects a non-string discovered issuer' do
      [123, ['https://idp.example.com'], { 'url' => 'https://idp.example.com' }, true].each do |value|
        result = check('https://idp.example.com', value)

        expect(result.reason).to eq(:invalid_discovered), "expected #{value.inspect} to be invalid"
        expect(result.discovered_string).to be_nil
      end
    end

    it 'rejects a missing configured issuer' do
      expect(check(nil, 'https://idp.example.com').reason).to eq(:missing_configured)
      expect(check('', 'https://idp.example.com').reason).to eq(:missing_configured)
    end

    it 'returns a frozen value object' do
      expect(check('https://idp.example.com', 'https://idp.example.com')).to be_frozen
    end
  end

  describe '.check_document' do
    it 'reads the issuer key from a parsed discovery document' do
      result = described_class.check_document(
        configured: 'https://idp.example.com',
        document: { 'issuer' => 'https://idp.example.com/' },
      )

      expect(result.reason).to eq(:mismatch)
      expect(result.discovered_string).to eq('https://idp.example.com/')
    end

    it 'treats a document without an issuer as missing' do
      result = described_class.check_document(configured: 'https://idp.example.com', document: {})

      expect(result.reason).to eq(:missing_discovered)
    end

    it 'treats a non-Hash document as missing' do
      result = described_class.check_document(configured: 'https://idp.example.com', document: ['issuer'])

      expect(result.reason).to eq(:missing_discovered)
    end
  end
end
