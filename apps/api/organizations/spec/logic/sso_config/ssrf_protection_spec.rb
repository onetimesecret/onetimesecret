# apps/api/organizations/spec/logic/sso_config/ssrf_protection_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::SsoConfig::SsrfProtection do
  # Test class that includes the module
  let(:test_class) do
    Class.new do
      include OrganizationAPI::Logic::SsoConfig::SsrfProtection
    end
  end

  subject(:protector) { test_class.new }

  describe '#valid_issuer_host?' do
    context 'with valid HTTPS URLs' do
      it 'returns true for valid HTTPS issuer URL' do
        expect(protector.valid_issuer_host?('https://login.microsoftonline.com/tenant')).to be true
      end

      it 'returns true for accounts.google.com' do
        expect(protector.valid_issuer_host?('https://accounts.google.com')).to be true
      end

      it 'returns true for external domain with path' do
        expect(protector.valid_issuer_host?('https://auth.example.com/oauth2/v1')).to be true
      end

      it 'returns true for URL with port' do
        expect(protector.valid_issuer_host?('https://auth.example.com:8443/issuer')).to be true
      end
    end

    context 'with HTTP URLs (not HTTPS)' do
      it 'returns false for HTTP URL' do
        expect(protector.valid_issuer_host?('http://login.microsoftonline.com/tenant')).to be false
      end

      it 'returns false for HTTP localhost' do
        expect(protector.valid_issuer_host?('http://localhost:8080')).to be false
      end
    end

    context 'with empty or missing host' do
      it 'returns false for empty string' do
        expect(protector.valid_issuer_host?('')).to be false
      end

      it 'returns false for nil coerced to string' do
        expect(protector.valid_issuer_host?('https://')).to be false
      end

      it 'returns false for URL with only scheme' do
        expect(protector.valid_issuer_host?('https:')).to be false
      end
    end

    context 'with malformed URIs' do
      it 'returns false for invalid URI syntax' do
        expect(protector.valid_issuer_host?('not a valid uri at all')).to be false
      end

      it 'returns false for URI with spaces' do
        expect(protector.valid_issuer_host?('https://example .com')).to be false
      end

      it 'returns false for URI with newlines' do
        expect(protector.valid_issuer_host?("https://example.com\n/path")).to be false
      end

      it 'returns false for non-string input that raises' do
        # URI.parse on integers or other types
        expect(protector.valid_issuer_host?(12345)).to be false
      end
    end

    context 'with internal hosts (SSRF prevention)' do
      it 'returns false for localhost' do
        expect(protector.valid_issuer_host?('https://localhost')).to be false
      end

      it 'returns false for localhost with port' do
        expect(protector.valid_issuer_host?('https://localhost:8443')).to be false
      end

      it 'returns false for .local domain' do
        expect(protector.valid_issuer_host?('https://myserver.local')).to be false
      end

      it 'returns false for .internal domain' do
        expect(protector.valid_issuer_host?('https://auth.internal')).to be false
      end

      it 'returns false for loopback IPv4' do
        expect(protector.valid_issuer_host?('https://127.0.0.1')).to be false
      end

      it 'returns false for private IPv4 10.x.x.x' do
        expect(protector.valid_issuer_host?('https://10.0.0.1')).to be false
      end

      it 'returns false for private IPv4 172.16.x.x' do
        expect(protector.valid_issuer_host?('https://172.16.0.1')).to be false
      end

      it 'returns false for private IPv4 192.168.x.x' do
        expect(protector.valid_issuer_host?('https://192.168.1.1')).to be false
      end
    end

    context 'with other protocol schemes' do
      it 'returns false for FTP scheme' do
        expect(protector.valid_issuer_host?('ftp://files.example.com')).to be false
      end

      it 'returns false for file scheme' do
        expect(protector.valid_issuer_host?('file:///etc/passwd')).to be false
      end

      it 'returns false for data scheme' do
        expect(protector.valid_issuer_host?('data:text/html,<h1>test</h1>')).to be false
      end
    end
  end

  describe '#internal_host?' do
    context 'with localhost and local domains' do
      it 'returns true for localhost' do
        expect(protector.internal_host?('localhost')).to be true
      end

      it 'returns true for .local suffix' do
        expect(protector.internal_host?('myserver.local')).to be true
      end

      it 'returns true for .internal suffix' do
        expect(protector.internal_host?('auth.internal')).to be true
      end

      it 'returns true for nested .local subdomain' do
        expect(protector.internal_host?('deep.nested.server.local')).to be true
      end
    end

    context 'with loopback addresses' do
      it 'returns true for 127.0.0.1' do
        expect(protector.internal_host?('127.0.0.1')).to be true
      end

      it 'returns true for 127.0.0.2 (loopback range)' do
        expect(protector.internal_host?('127.0.0.2')).to be true
      end

      it 'returns true for IPv6 loopback ::1' do
        expect(protector.internal_host?('::1')).to be true
      end
    end

    context 'with private IPv4 ranges' do
      it 'returns true for 10.0.0.0/8 range' do
        expect(protector.internal_host?('10.255.255.255')).to be true
      end

      it 'returns true for 172.16.0.0/12 range' do
        expect(protector.internal_host?('172.31.255.255')).to be true
      end

      it 'returns true for 192.168.0.0/16 range' do
        expect(protector.internal_host?('192.168.255.255')).to be true
      end
    end

    context 'with link-local addresses' do
      it 'returns true for IPv4 link-local 169.254.x.x' do
        expect(protector.internal_host?('169.254.1.1')).to be true
      end

      it 'returns true for IPv6 link-local fe80::' do
        expect(protector.internal_host?('fe80::1')).to be true
      end

      it 'returns true for IPv6 link-local with interface' do
        # Note: IPAddr may not parse zone IDs, but fe80:: prefix should match
        expect(protector.internal_host?('fe80::1234:5678:abcd:ef01')).to be true
      end
    end

    context 'with IPv6 private addresses' do
      it 'returns true for IPv6 unique local fc00::/7' do
        expect(protector.internal_host?('fc00::1')).to be true
      end

      it 'returns true for IPv6 unique local fd00::/8' do
        expect(protector.internal_host?('fd00::1')).to be true
      end
    end

    context 'with public addresses' do
      it 'returns false for public IPv4' do
        expect(protector.internal_host?('8.8.8.8')).to be false
      end

      it 'returns false for another public IPv4' do
        expect(protector.internal_host?('93.184.216.34')).to be false
      end

      it 'returns false for public IPv6' do
        expect(protector.internal_host?('2001:4860:4860::8888')).to be false
      end
    end

    context 'with hostname edge cases' do
      it 'returns false for valid external hostname' do
        expect(protector.internal_host?('login.microsoftonline.com')).to be false
      end

      it 'returns false for hostname containing localhost as substring' do
        expect(protector.internal_host?('notlocalhost.example.com')).to be false
      end

      it 'returns false for hostname ending with local as part of word' do
        expect(protector.internal_host?('notlocal.example.com')).to be false
      end

      it 'returns false for empty string (invalid but not internal)' do
        # Empty string is not localhost, not .local, not .internal
        # IPAddr.new('') will raise, so returns false
        expect(protector.internal_host?('')).to be false
      end
    end

    context 'with edge case IPv4 representations' do
      it 'returns false for 0.0.0.0 (not caught by loopback/private/link-local)' do
        # Note: 0.0.0.0 is technically "unspecified" but IPAddr does not consider it
        # loopback, private, or link-local. This may be a gap to address if needed.
        expect(protector.internal_host?('0.0.0.0')).to be false
      end

      it 'returns false for 172.15.0.1 (just outside private range)' do
        expect(protector.internal_host?('172.15.0.1')).to be false
      end

      it 'returns false for 172.32.0.1 (just outside private range)' do
        expect(protector.internal_host?('172.32.0.1')).to be false
      end
    end

    context 'with IPv6-mapped IPv4 addresses' do
      it 'returns true for IPv6-mapped loopback ::ffff:127.0.0.1' do
        # IPv6-mapped IPv4 addresses can bypass naive IPv4-only checks
        expect(protector.internal_host?('::ffff:127.0.0.1')).to be true
      end

      it 'returns true for IPv6-mapped private ::ffff:10.0.0.1' do
        expect(protector.internal_host?('::ffff:10.0.0.1')).to be true
      end

      it 'returns true for IPv6-mapped private ::ffff:192.168.1.1' do
        expect(protector.internal_host?('::ffff:192.168.1.1')).to be true
      end

      it 'returns true for IPv6-mapped private ::ffff:172.16.0.1' do
        expect(protector.internal_host?('::ffff:172.16.0.1')).to be true
      end
    end

    context 'with cloud metadata IP addresses' do
      it 'returns true for AWS/GCP metadata IP 169.254.169.254' do
        # Cloud metadata endpoint - must be blocked to prevent credential theft
        expect(protector.internal_host?('169.254.169.254')).to be true
      end

      it 'returns true for link-local metadata range 169.254.0.1' do
        expect(protector.internal_host?('169.254.0.1')).to be true
      end
    end
  end

  describe '#valid_issuer_host?' do
    context 'with URLs containing credentials' do
      it 'accepts URL with embedded credentials (URI parsing extracts host correctly)' do
        # URIs with credentials like https://user:pass@host are valid syntax
        # The host extraction works correctly, so validation depends on the host itself
        # Note: Whether to allow embedded credentials is a policy decision;
        # currently we only validate the host, not the userinfo component
        expect(protector.valid_issuer_host?('https://user:pass@login.microsoftonline.com')).to be true
      end

      it 'rejects URL with credentials pointing to internal host' do
        # Even with credentials, internal hosts must be rejected
        expect(protector.valid_issuer_host?('https://user:pass@localhost')).to be false
      end

      it 'rejects URL with credentials pointing to private IP' do
        expect(protector.valid_issuer_host?('https://admin:secret@192.168.1.1/auth')).to be false
      end
    end

    context 'with cloud metadata URLs' do
      it 'rejects AWS/GCP metadata endpoint' do
        # Critical SSRF vector for cloud credential theft
        expect(protector.valid_issuer_host?('https://169.254.169.254/latest/meta-data/')).to be false
      end

      it 'rejects Azure metadata endpoint (link-local)' do
        expect(protector.valid_issuer_host?('https://169.254.169.254/metadata/instance')).to be false
      end
    end

    context 'with IPv6-mapped IPv4 URLs' do
      it 'rejects IPv6-mapped loopback' do
        expect(protector.valid_issuer_host?('https://[::ffff:127.0.0.1]/auth')).to be false
      end

      it 'rejects IPv6-mapped private network' do
        expect(protector.valid_issuer_host?('https://[::ffff:10.0.0.1]/auth')).to be false
      end
    end
  end
end
