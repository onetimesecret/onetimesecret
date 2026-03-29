# apps/api/domains/spec/logic/sso_config/ssrf_protection_spec.rb
#
# frozen_string_literal: true

# Unit tests for SSRF Protection module
#
# Issue: #2786 - Per-domain SSO configuration
#
# The SsrfProtection module validates issuer URLs to prevent Server-Side
# Request Forgery when OmniAuth OIDC performs discovery. These tests
# verify the module in isolation without requiring HTTP or DNS.
#
# Run:
#   pnpm run test:rspec apps/api/domains/spec/logic/sso_config/ssrf_protection_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Load the module under test
require_relative '../../../../../../apps/api/domains/logic/sso_config/ssrf_protection'

RSpec.describe DomainsAPI::Logic::SsoConfig::SsrfProtection do
  # Include the module in a test harness so we can call its methods directly
  let(:validator) do
    Object.new.tap { |obj| obj.extend(described_class) }
  end

  # Stub DNS resolution by default so tests are deterministic and fast.
  # Individual examples override this when testing DNS behavior.
  before do
    allow(Resolv).to receive(:getaddresses).and_return([])
  end

  # ==========================================================================
  # valid_issuer_host? - Scheme Enforcement
  # ==========================================================================

  describe '#valid_issuer_host?' do
    context 'scheme validation' do
      it 'accepts HTTPS URLs' do
        expect(validator.valid_issuer_host?('https://idp.example.com')).to be true
      end

      it 'rejects HTTP URLs' do
        expect(validator.valid_issuer_host?('http://idp.example.com')).to be false
      end

      it 'rejects FTP URLs' do
        expect(validator.valid_issuer_host?('ftp://idp.example.com')).to be false
      end

      it 'rejects scheme-less URLs' do
        expect(validator.valid_issuer_host?('idp.example.com')).to be false
      end
    end

    # ========================================================================
    # valid_issuer_host? - Localhost / Loopback Rejection
    # ========================================================================

    context 'localhost and loopback addresses' do
      it 'rejects localhost by name' do
        expect(validator.valid_issuer_host?('https://localhost/.well-known/openid-configuration')).to be false
      end

      it 'rejects 127.0.0.1' do
        expect(validator.valid_issuer_host?('https://127.0.0.1')).to be false
      end

      it 'rejects IPv6 loopback ::1' do
        expect(validator.valid_issuer_host?('https://[::1]')).to be false
      end

      it 'rejects 127.x.x.x variants' do
        expect(validator.valid_issuer_host?('https://127.0.0.2')).to be false
      end
    end

    # ========================================================================
    # valid_issuer_host? - Private IP Range Rejection
    # ========================================================================

    context 'private IP ranges (RFC 1918)' do
      it 'rejects 10.0.0.0/8' do
        expect(validator.valid_issuer_host?('https://10.0.0.1')).to be false
      end

      it 'rejects 10.255.255.255' do
        expect(validator.valid_issuer_host?('https://10.255.255.255')).to be false
      end

      it 'rejects 172.16.0.0/12 low end' do
        expect(validator.valid_issuer_host?('https://172.16.0.1')).to be false
      end

      it 'rejects 172.31.255.255 high end' do
        expect(validator.valid_issuer_host?('https://172.31.255.255')).to be false
      end

      it 'rejects 192.168.0.0/16' do
        expect(validator.valid_issuer_host?('https://192.168.1.1')).to be false
      end

      it 'rejects 192.168.255.255' do
        expect(validator.valid_issuer_host?('https://192.168.255.255')).to be false
      end
    end

    # ========================================================================
    # valid_issuer_host? - Link-Local Rejection
    # ========================================================================

    context 'link-local addresses' do
      it 'rejects 169.254.x.x (AWS metadata endpoint range)' do
        expect(validator.valid_issuer_host?('https://169.254.169.254')).to be false
      end

      it 'rejects 169.254.0.1' do
        expect(validator.valid_issuer_host?('https://169.254.0.1')).to be false
      end
    end

    # ========================================================================
    # valid_issuer_host? - Internal Hostname Rejection
    # ========================================================================

    context 'internal hostnames' do
      it 'rejects .local hostnames' do
        expect(validator.valid_issuer_host?('https://keycloak.local')).to be false
      end

      it 'rejects .internal hostnames' do
        expect(validator.valid_issuer_host?('https://idp.corp.internal')).to be false
      end
    end

    # ========================================================================
    # valid_issuer_host? - Valid Public URLs
    # ========================================================================

    context 'valid public URLs' do
      it 'accepts a standard IdP URL' do
        expect(validator.valid_issuer_host?('https://login.microsoftonline.com/tenant-id/v2.0')).to be true
      end

      it 'accepts accounts.google.com' do
        expect(validator.valid_issuer_host?('https://accounts.google.com')).to be true
      end

      it 'accepts a custom domain IdP' do
        expect(validator.valid_issuer_host?('https://auth.company.com')).to be true
      end

      it 'accepts URL with a port number' do
        expect(validator.valid_issuer_host?('https://idp.example.com:8443')).to be true
      end

      it 'accepts URL with a path' do
        expect(validator.valid_issuer_host?('https://idp.example.com/realms/myrealm')).to be true
      end
    end

    # ========================================================================
    # valid_issuer_host? - Malformed / Edge-Case Input
    # ========================================================================

    context 'malformed and edge-case input' do
      it 'returns false for empty string' do
        expect(validator.valid_issuer_host?('')).to be false
      end

      it 'returns false for nil' do
        expect(validator.valid_issuer_host?(nil)).to be false
      end

      it 'returns false for garbage string' do
        expect(validator.valid_issuer_host?('not a url at all')).to be false
      end

      it 'returns false for URL with only scheme' do
        expect(validator.valid_issuer_host?('https://')).to be false
      end

      it 'does not raise on malformed URI characters' do
        expect { validator.valid_issuer_host?('https://evil host with spaces') }.not_to raise_error
        expect(validator.valid_issuer_host?('https://evil host with spaces')).to be false
      end
    end
  end

  # ==========================================================================
  # internal_host? - Direct Testing
  # ==========================================================================

  describe '#internal_host?' do
    it 'returns true for localhost' do
      expect(validator.internal_host?('localhost')).to be true
    end

    it 'returns true for .local suffix' do
      expect(validator.internal_host?('myhost.local')).to be true
    end

    it 'returns true for .internal suffix' do
      expect(validator.internal_host?('db.cluster.internal')).to be true
    end

    it 'returns false for a public hostname' do
      expect(validator.internal_host?('auth.example.com')).to be false
    end

    it 'returns true for 10.x private IP' do
      expect(validator.internal_host?('10.0.0.5')).to be true
    end

    it 'returns true for 172.16.x private IP' do
      expect(validator.internal_host?('172.20.0.1')).to be true
    end

    it 'returns true for 192.168.x private IP' do
      expect(validator.internal_host?('192.168.0.1')).to be true
    end

    it 'returns true for IPv6 loopback' do
      expect(validator.internal_host?('::1')).to be true
    end

    it 'returns true for link-local 169.254.169.254' do
      expect(validator.internal_host?('169.254.169.254')).to be true
    end
  end

  # ==========================================================================
  # resolves_to_internal_ip? - DNS Rebinding Protection
  # ==========================================================================

  describe '#resolves_to_internal_ip?' do
    context 'when hostname resolves to a private IP' do
      before do
        allow(Resolv).to receive(:getaddresses)
          .with('evil.example.com')
          .and_return(['10.0.0.1'])
      end

      it 'returns true (blocks the bypass)' do
        expect(validator.resolves_to_internal_ip?('evil.example.com')).to be true
      end
    end

    context 'when hostname resolves to a loopback IP' do
      before do
        allow(Resolv).to receive(:getaddresses)
          .with('localtest.me')
          .and_return(['127.0.0.1'])
      end

      it 'returns true' do
        expect(validator.resolves_to_internal_ip?('localtest.me')).to be true
      end
    end

    context 'when hostname resolves to a link-local IP' do
      before do
        allow(Resolv).to receive(:getaddresses)
          .with('metadata.cloud')
          .and_return(['169.254.169.254'])
      end

      it 'returns true' do
        expect(validator.resolves_to_internal_ip?('metadata.cloud')).to be true
      end
    end

    context 'when hostname resolves to a public IP' do
      before do
        allow(Resolv).to receive(:getaddresses)
          .with('safe.example.com')
          .and_return(['93.184.216.34'])
      end

      it 'returns false' do
        expect(validator.resolves_to_internal_ip?('safe.example.com')).to be false
      end
    end

    context 'when hostname resolves to mixed public and private IPs' do
      before do
        allow(Resolv).to receive(:getaddresses)
          .with('sneaky.example.com')
          .and_return(['93.184.216.34', '10.0.0.1'])
      end

      it 'returns true (any internal IP is a rejection)' do
        expect(validator.resolves_to_internal_ip?('sneaky.example.com')).to be true
      end
    end

    context 'when DNS resolution fails' do
      before do
        allow(Resolv).to receive(:getaddresses)
          .with('nonexistent.example.com')
          .and_raise(Resolv::ResolvError)
      end

      it 'returns true (fail-closed)' do
        expect(validator.resolves_to_internal_ip?('nonexistent.example.com')).to be true
      end
    end

    context 'when DNS resolution times out' do
      before do
        allow(Resolv).to receive(:getaddresses)
          .with('slow.example.com')
          .and_raise(Resolv::ResolvTimeout)
      end

      it 'returns true (fail-closed)' do
        expect(validator.resolves_to_internal_ip?('slow.example.com')).to be true
      end
    end
  end
end
