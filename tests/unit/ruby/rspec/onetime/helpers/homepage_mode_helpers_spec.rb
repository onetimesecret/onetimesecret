# tests/unit/ruby/rspec/onetime/helpers/homepage_mode_helpers_spec.rb
# frozen_string_literal: true

require_relative '../../spec_helper'
require 'ipaddr'

# Test class that includes the module for testing
class HomepageModeTestClass
  include Onetime::Helpers::HomepageModeHelpers
  attr_accessor :req

  def initialize(req = nil)
    @req = req
  end
end

RSpec.describe Onetime::Helpers::HomepageModeHelpers do
  let(:test_instance) { HomepageModeTestClass.new }

  describe '#validate_cidr_privacy' do
    context 'with IPv4 CIDR blocks' do
      context 'with broad ranges (MORE PRIVATE - should be ACCEPTED)' do
        it 'accepts /8 CIDR (16,777,214 IPs) - very broad, very private' do
          cidr = IPAddr.new('10.0.0.0/8')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected /8 to be accepted (broad = private)"
        end

        it 'accepts /16 CIDR (65,534 IPs) - broad, privacy-preserving' do
          cidr = IPAddr.new('192.168.0.0/16')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected /16 to be accepted (broad = private)"
        end

        it 'accepts /17 CIDR (32,766 IPs) - broad, privacy-preserving' do
          cidr = IPAddr.new('172.116.128.0/17')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected /17 to be accepted (broad = private)"
        end

        it 'accepts /20 CIDR (4,094 IPs) - broad, privacy-preserving' do
          cidr = IPAddr.new('10.105.64.0/20')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected /20 to be accepted (broad = private)"
        end

        it 'accepts /23 CIDR (510 IPs) - reasonably broad' do
          cidr = IPAddr.new('192.168.1.0/23')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected /23 to be accepted (reasonably broad)"
        end

        it 'accepts /24 CIDR (254 IPs) - minimum acceptable breadth' do
          cidr = IPAddr.new('192.168.1.0/24')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected /24 to be accepted (minimum threshold)"
        end
      end

      context 'with narrow ranges (LESS PRIVATE - should be REJECTED)' do
        it 'rejects /25 CIDR (126 IPs) - too narrow, insufficient privacy' do
          cidr = IPAddr.new('192.168.1.0/25')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(false), "Expected /25 to be rejected (too narrow)"
        end

        it 'rejects /28 CIDR (14 IPs) - very narrow, can target small groups' do
          cidr = IPAddr.new('192.168.1.0/28')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(false), "Expected /28 to be rejected (very narrow)"
        end

        it 'rejects /30 CIDR (2 IPs) - extremely narrow, point-to-point link' do
          cidr = IPAddr.new('192.168.1.0/30')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(false), "Expected /30 to be rejected (extremely narrow)"
        end

        it 'rejects /31 CIDR (2 IPs for point-to-point) - RFC 3021 point-to-point' do
          cidr = IPAddr.new('192.168.1.0/31')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(false), "Expected /31 to be rejected (point-to-point link)"
        end

        it 'rejects /32 CIDR (1 IP) - single host, no privacy protection' do
          cidr = IPAddr.new('192.168.1.1/32')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(false), "Expected /32 to be rejected (single host, no privacy)"
        end
      end

      context 'with real-world examples from the bug report' do
        it 'accepts X.105.64.0/20 (4,094 IPs) - currently being REJECTED incorrectly' do
          cidr = IPAddr.new('10.105.64.0/20')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected /20 to be accepted - currently failing due to bug"
        end

        it 'accepts A.116.128.0/17 (32,766 IPs) - currently being REJECTED incorrectly' do
          cidr = IPAddr.new('172.116.128.0/17')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected /17 to be accepted - currently failing due to bug"
        end

        it 'accepts B.10.0.0/17 (32,766 IPs) - currently being REJECTED incorrectly' do
          cidr = IPAddr.new('192.10.0.0/17')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected /17 to be accepted - currently failing due to bug"
        end
      end
    end

    context 'with IPv6 CIDR blocks' do
      context 'with broad ranges (MORE PRIVATE - should be ACCEPTED)' do
        it 'accepts /32 IPv6 CIDR - broad allocation' do
          cidr = IPAddr.new('2001:db8::/32')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected IPv6 /32 to be accepted (broad)"
        end

        it 'accepts /40 IPv6 CIDR - large organizational block' do
          cidr = IPAddr.new('2001:db8:1234::/40')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected IPv6 /40 to be accepted (large org)"
        end

        it 'accepts /48 IPv6 CIDR - standard site allocation, minimum acceptable' do
          cidr = IPAddr.new('2001:db8:1234::/48')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(true), "Expected IPv6 /48 to be accepted (minimum threshold)"
        end
      end

      context 'with narrow ranges (LESS PRIVATE - should be REJECTED)' do
        it 'rejects /56 IPv6 CIDR - too narrow for privacy' do
          cidr = IPAddr.new('2001:db8:1234::/56')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(false), "Expected IPv6 /56 to be rejected (too narrow)"
        end

        it 'rejects /64 IPv6 CIDR - single subnet, insufficient privacy' do
          cidr = IPAddr.new('2001:db8:1234:5678::/64')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(false), "Expected IPv6 /64 to be rejected (single subnet)"
        end

        it 'rejects /80 IPv6 CIDR - very narrow range' do
          cidr = IPAddr.new('2001:db8:1234:5678:9abc::/80')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(false), "Expected IPv6 /80 to be rejected (very narrow)"
        end

        it 'rejects /128 IPv6 CIDR - single host, no privacy' do
          cidr = IPAddr.new('2001:db8::1/128')
          result = test_instance.send(:validate_cidr_privacy, cidr)
          expect(result).to eq(false), "Expected IPv6 /128 to be rejected (single host)"
        end
      end
    end

    context 'with edge cases' do
      it 'accepts IPv4 /0 (entire internet) - maximally broad' do
        cidr = IPAddr.new('0.0.0.0/0')
        result = test_instance.send(:validate_cidr_privacy, cidr)
        expect(result).to eq(true), "Expected /0 to be accepted (maximally broad)"
      end

      it 'accepts IPv6 /0 (entire internet) - maximally broad' do
        cidr = IPAddr.new('::/0')
        result = test_instance.send(:validate_cidr_privacy, cidr)
        expect(result).to eq(true), "Expected IPv6 /0 to be accepted (maximally broad)"
      end
    end
  end

  describe '#compile_homepage_cidrs' do
    let(:mock_req) { double('request', env: {}) }

    before do
      test_instance.req = mock_req
      # Suppress logging during tests
      allow(OT).to receive(:info)
      allow(OT).to receive(:le)
      allow(OT).to receive(:ld)
    end

    context 'with valid privacy-preserving CIDRs' do
      it 'compiles broad IPv4 ranges that should be accepted' do
        config = {
          matching_cidrs: [
            '10.0.0.0/8',      # Very broad - should be accepted
            '172.16.0.0/16',   # Broad - should be accepted
            '192.168.0.0/24',  # Minimum acceptable - should be accepted
          ]
        }

        result = test_instance.send(:compile_homepage_cidrs, config)

        expect(result).to be_an(Array)
        expect(result.length).to eq(3), "Expected all 3 broad CIDRs to be accepted"
        expect(result.all? { |cidr| cidr.is_a?(IPAddr) }).to be true
      end

      it 'compiles the real-world CIDRs from the bug report (currently failing)' do
        config = {
          matching_cidrs: [
            '10.105.64.0/20',    # 4,094 IPs - should be accepted
            '172.116.128.0/17',  # 32,766 IPs - should be accepted
            '192.10.0.0/17',     # 32,766 IPs - should be accepted
          ]
        }

        result = test_instance.send(:compile_homepage_cidrs, config)

        # These are currently being rejected by the buggy code
        # Once fixed, all 3 should be accepted
        expect(result).to be_an(Array)
        expect(result.length).to eq(3), "Expected all 3 broad CIDRs from logs to be accepted"
      end

      it 'compiles broad IPv6 ranges that should be accepted' do
        config = {
          matching_cidrs: [
            '2001:db8::/32',     # Very broad - should be accepted
            '2001:db8:1234::/48', # Minimum acceptable - should be accepted
          ]
        }

        result = test_instance.send(:compile_homepage_cidrs, config)

        expect(result).to be_an(Array)
        expect(result.length).to eq(2), "Expected both broad IPv6 CIDRs to be accepted"
      end
    end

    context 'with narrow CIDRs that violate privacy' do
      it 'rejects narrow IPv4 ranges and logs privacy violations' do
        config = {
          matching_cidrs: [
            '192.168.1.1/32',  # Single host - should be rejected
            '192.168.1.0/28',  # 14 IPs - should be rejected
            '192.168.1.0/30',  # 2 IPs - should be rejected
          ]
        }

        expect(OT).to receive(:info).with('[homepage_mode] CIDR rejected for privacy', hash_including(:cidr, :prefix)).at_least(3).times

        result = test_instance.send(:compile_homepage_cidrs, config)

        expect(result).to be_an(Array)
        expect(result).to be_empty, "Expected all narrow CIDRs to be rejected"
      end

      it 'rejects narrow IPv6 ranges and logs privacy violations' do
        config = {
          matching_cidrs: [
            '2001:db8::1/128',      # Single host - should be rejected
            '2001:db8:1234::/64',   # Single subnet - should be rejected
            '2001:db8:1234::/56',   # Too narrow - should be rejected
          ]
        }

        expect(OT).to receive(:info).with('[homepage_mode] CIDR rejected for privacy', hash_including(:cidr, :prefix)).at_least(3).times

        result = test_instance.send(:compile_homepage_cidrs, config)

        expect(result).to be_an(Array)
        expect(result).to be_empty, "Expected all narrow IPv6 CIDRs to be rejected"
      end
    end

    context 'with mixed valid and invalid CIDRs' do
      it 'accepts broad CIDRs and rejects narrow ones' do
        config = {
          matching_cidrs: [
            '10.0.0.0/16',       # Broad - should be accepted
            '192.168.1.1/32',    # Single host - should be rejected
            '172.16.0.0/20',     # Broad - should be accepted
            '192.168.2.0/28',    # Narrow - should be rejected
            '10.10.0.0/24',      # Minimum acceptable - should be accepted
          ]
        }

        expect(OT).to receive(:info).with('[homepage_mode] CIDR rejected for privacy', hash_including(:cidr, :prefix)).at_least(2).times

        result = test_instance.send(:compile_homepage_cidrs, config)

        expect(result).to be_an(Array)
        expect(result.length).to eq(3), "Expected 3 broad CIDRs to be accepted, 2 narrow ones rejected"
      end
    end

    context 'with invalid CIDR strings' do
      it 'handles invalid CIDR syntax gracefully' do
        config = {
          matching_cidrs: [
            'not-a-cidr',
            '999.999.999.999/24',
            'invalid',
          ]
        }

        expect(OT).to receive(:le).with('[homepage_mode] Invalid CIDR', hash_including(:cidr, :error)).at_least(3).times

        result = test_instance.send(:compile_homepage_cidrs, config)

        expect(result).to be_an(Array)
        expect(result).to be_empty
      end

      it 'continues processing valid CIDRs after encountering invalid ones' do
        config = {
          matching_cidrs: [
            '10.0.0.0/16',       # Valid broad - should be accepted
            'invalid-cidr',      # Invalid - should be skipped
            '172.16.0.0/20',     # Valid broad - should be accepted
          ]
        }

        expect(OT).to receive(:le).with('[homepage_mode] Invalid CIDR', hash_including(:cidr)).once

        result = test_instance.send(:compile_homepage_cidrs, config)

        expect(result).to be_an(Array)
        expect(result.length).to eq(2), "Expected 2 valid CIDRs to be compiled despite invalid one"
      end
    end

    context 'with empty or missing configuration' do
      it 'returns empty array when matching_cidrs is empty' do
        config = { matching_cidrs: [] }
        result = test_instance.send(:compile_homepage_cidrs, config)
        expect(result).to eq([])
      end

      it 'returns empty array when matching_cidrs is nil' do
        config = { matching_cidrs: nil }
        result = test_instance.send(:compile_homepage_cidrs, config)
        expect(result).to eq([])
      end

      it 'returns empty array when matching_cidrs key is missing' do
        config = {}
        result = test_instance.send(:compile_homepage_cidrs, config)
        expect(result).to eq([])
      end
    end
  end

  describe 'CIDR privacy logic explanation' do
    it 'documents the correct understanding of CIDR prefix numbers' do
      # This test documents the correct understanding for future reference
      #
      # CIDR PREFIX LOGIC (smaller number = broader range = MORE PRIVATE):
      #
      # IPv4:
      # /8  = 16,777,214 IPs = VERY BROAD   = VERY PRIVATE     ✓ Accept
      # /16 = 65,534 IPs     = BROAD        = VERY PRIVATE     ✓ Accept
      # /17 = 32,766 IPs     = BROAD        = VERY PRIVATE     ✓ Accept
      # /20 = 4,094 IPs      = BROAD        = PRIVACY OK       ✓ Accept
      # /24 = 254 IPs        = NARROW       = MINIMUM PRIVACY  ✓ Accept (threshold)
      # /28 = 14 IPs         = VERY NARROW  = INSUFFICIENT     ✗ Reject
      # /32 = 1 IP           = SINGLE HOST  = NO PRIVACY       ✗ Reject
      #
      # IPv6:
      # /32 = 2^96 IPs       = VERY BROAD   = VERY PRIVATE     ✓ Accept
      # /48 = 2^80 IPs       = BROAD        = MINIMUM PRIVACY  ✓ Accept (threshold)
      # /64 = 2^64 IPs       = NARROW       = INSUFFICIENT     ✗ Reject
      # /128 = 1 IP          = SINGLE HOST  = NO PRIVACY       ✗ Reject
      #
      # THE RULE: prefix <= max_prefix (not >= min_prefix)
      #           For IPv4: prefix <= 24 (accepts /1 through /24, rejects /25 through /32)
      #           For IPv6: prefix <= 48 (accepts /1 through /48, rejects /49 through /128)

      expect(true).to eq(true) # This test exists for documentation
    end
  end

  describe '#private_ip?' do
    context 'with IPv4 private addresses' do
      it 'identifies RFC 1918 10.0.0.0/8 as private' do
        expect(test_instance.send(:private_ip?, '10.0.0.1')).to be true
        expect(test_instance.send(:private_ip?, '10.255.255.254')).to be true
      end

      it 'identifies RFC 1918 172.16.0.0/12 as private' do
        expect(test_instance.send(:private_ip?, '172.16.0.1')).to be true
        expect(test_instance.send(:private_ip?, '172.31.255.254')).to be true
      end

      it 'identifies RFC 1918 192.168.0.0/16 as private' do
        expect(test_instance.send(:private_ip?, '192.168.0.1')).to be true
        expect(test_instance.send(:private_ip?, '192.168.255.254')).to be true
      end

      it 'identifies loopback 127.0.0.0/8 as private' do
        expect(test_instance.send(:private_ip?, '127.0.0.1')).to be true
        expect(test_instance.send(:private_ip?, '127.255.255.254')).to be true
      end

      it 'identifies link-local 169.254.0.0/16 as private' do
        expect(test_instance.send(:private_ip?, '169.254.0.1')).to be true
        expect(test_instance.send(:private_ip?, '169.254.255.254')).to be true
      end
    end

    context 'with IPv4 public addresses' do
      it 'identifies public IPs as not private' do
        expect(test_instance.send(:private_ip?, '1.1.1.1')).to be false
        expect(test_instance.send(:private_ip?, '8.8.8.8')).to be false
        expect(test_instance.send(:private_ip?, '93.184.216.34')).to be false
        expect(test_instance.send(:private_ip?, '151.101.1.140')).to be false
      end

      it 'identifies edge cases near private ranges as public' do
        expect(test_instance.send(:private_ip?, '9.255.255.255')).to be false   # Just before 10.0.0.0/8
        expect(test_instance.send(:private_ip?, '11.0.0.0')).to be false        # Just after 10.0.0.0/8
        expect(test_instance.send(:private_ip?, '172.15.255.255')).to be false  # Just before 172.16.0.0/12
        expect(test_instance.send(:private_ip?, '172.32.0.0')).to be false      # Just after 172.31.0.0/12
        expect(test_instance.send(:private_ip?, '192.167.255.255')).to be false # Just before 192.168.0.0/16
        expect(test_instance.send(:private_ip?, '192.169.0.0')).to be false     # Just after 192.168.0.0/16
      end
    end

    context 'with IPv6 addresses' do
      it 'identifies IPv6 loopback as private' do
        expect(test_instance.send(:private_ip?, '::1')).to be true
      end

      it 'identifies IPv6 unique local addresses (fc00::/7) as private' do
        expect(test_instance.send(:private_ip?, 'fc00::1')).to be true
        expect(test_instance.send(:private_ip?, 'fd00::1')).to be true
        expect(test_instance.send(:private_ip?, 'fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')).to be true
      end

      it 'identifies IPv6 link-local addresses (fe80::/10) as private' do
        expect(test_instance.send(:private_ip?, 'fe80::1')).to be true
        expect(test_instance.send(:private_ip?, 'febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff')).to be true
      end

      it 'identifies public IPv6 addresses as not private' do
        expect(test_instance.send(:private_ip?, '2001:4860:4860::8888')).to be false  # Google DNS
        expect(test_instance.send(:private_ip?, '2606:4700:4700::1111')).to be false  # Cloudflare DNS
      end
    end

    context 'with invalid or empty inputs' do
      it 'treats nil as private (safe default)' do
        expect(test_instance.send(:private_ip?, nil)).to be true
      end

      it 'treats empty string as private (safe default)' do
        expect(test_instance.send(:private_ip?, '')).to be true
      end

      it 'treats invalid IP address as private (safe default)' do
        expect(test_instance.send(:private_ip?, 'not-an-ip')).to be true
        expect(test_instance.send(:private_ip?, '999.999.999.999')).to be true
      end
    end
  end

  describe '#extract_x_forwarded_for' do
    let(:mock_req) { double('request', env: {}) }

    before do
      test_instance.req = mock_req
    end

    it 'extracts single IP from X-Forwarded-For header' do
      mock_req.env['HTTP_X_FORWARDED_FOR'] = '203.0.113.0'
      result = test_instance.send(:extract_x_forwarded_for)
      expect(result).to eq(['203.0.113.0'])
    end

    it 'extracts multiple IPs from X-Forwarded-For header' do
      mock_req.env['HTTP_X_FORWARDED_FOR'] = '203.0.113.0, 198.51.100.0, 192.0.2.0'
      result = test_instance.send(:extract_x_forwarded_for)
      expect(result).to eq(['203.0.113.0', '198.51.100.0', '192.0.2.0'])
    end

    it 'strips whitespace from IPs' do
      mock_req.env['HTTP_X_FORWARDED_FOR'] = '  203.0.113.0  ,  198.51.100.0  '
      result = test_instance.send(:extract_x_forwarded_for)
      expect(result).to eq(['203.0.113.0', '198.51.100.0'])
    end

    it 'returns nil when header is not present' do
      result = test_instance.send(:extract_x_forwarded_for)
      expect(result).to be_nil
    end

    it 'returns nil when header is empty' do
      mock_req.env['HTTP_X_FORWARDED_FOR'] = ''
      result = test_instance.send(:extract_x_forwarded_for)
      expect(result).to be_nil
    end
  end

  describe '#extract_rfc7239_forwarded' do
    let(:mock_req) { double('request', env: {}) }

    before do
      test_instance.req = mock_req
    end

    it 'extracts single IP from RFC 7239 Forwarded header' do
      mock_req.env['HTTP_FORWARDED'] = 'for=203.0.113.0'
      result = test_instance.send(:extract_rfc7239_forwarded)
      expect(result).to eq(['203.0.113.0'])
    end

    it 'extracts multiple IPs from Forwarded header' do
      mock_req.env['HTTP_FORWARDED'] = 'for=203.0.113.0, for=198.51.100.0'
      result = test_instance.send(:extract_rfc7239_forwarded)
      expect(result).to eq(['203.0.113.0', '198.51.100.0'])
    end

    it 'extracts IPs with quoted values' do
      mock_req.env['HTTP_FORWARDED'] = 'for="203.0.113.0"'
      result = test_instance.send(:extract_rfc7239_forwarded)
      expect(result).to eq(['203.0.113.0'])
    end

    it 'extracts IPv6 addresses with brackets' do
      mock_req.env['HTTP_FORWARDED'] = 'for="[2001:db8::1]"'
      result = test_instance.send(:extract_rfc7239_forwarded)
      expect(result).to eq(['2001:db8::1'])
    end

    it 'extracts IPs from complex Forwarded header with multiple parameters' do
      mock_req.env['HTTP_FORWARDED'] = 'for=203.0.113.0;by=198.51.100.0, for=192.0.2.0'
      result = test_instance.send(:extract_rfc7239_forwarded)
      expect(result).to eq(['203.0.113.0', '192.0.2.0'])
    end

    it 'handles case-insensitive for parameter' do
      mock_req.env['HTTP_FORWARDED'] = 'For=203.0.113.0, FOR=198.51.100.0'
      result = test_instance.send(:extract_rfc7239_forwarded)
      expect(result).to eq(['203.0.113.0', '198.51.100.0'])
    end

    it 'returns nil when header is not present' do
      result = test_instance.send(:extract_rfc7239_forwarded)
      expect(result).to be_nil
    end

    it 'returns nil when header is empty' do
      mock_req.env['HTTP_FORWARDED'] = ''
      result = test_instance.send(:extract_rfc7239_forwarded)
      expect(result).to be_nil
    end
  end

  describe '#extract_ip_from_header' do
    let(:mock_req) { double('request', env: {}) }

    before do
      test_instance.req = mock_req
      allow(OT).to receive(:ld)
    end

    context 'with trusted_proxy_depth of 1' do
      it 'extracts client IP from X-Forwarded-For chain' do
        # Chain: client -> proxy1
        # X-Forwarded-For: client_ip, proxy1_ip
        mock_req.env['HTTP_X_FORWARDED_FOR'] = '203.0.113.0, 198.51.100.0'
        result = test_instance.send(:extract_ip_from_header, 'X-Forwarded-For', 1)
        expect(result).to eq('203.0.113.0')
      end
    end

    context 'with trusted_proxy_depth of 2' do
      it 'extracts correct client IP from longer chain' do
        # Chain: client -> proxy1 -> proxy2
        # X-Forwarded-For: client_ip, proxy1_ip, proxy2_ip
        # Logic: Remove last 2 IPs (proxies), take rightmost of what's left
        mock_req.env['HTTP_X_FORWARDED_FOR'] = '203.0.113.0, 198.51.100.0, 192.0.2.0'
        result = test_instance.send(:extract_ip_from_header, 'X-Forwarded-For', 2)
        expect(result).to eq('203.0.113.0')
      end

      it 'extracts correct client IP from even longer chain' do
        # Chain: client -> intermediate -> proxy1 -> proxy2
        # X-Forwarded-For: client_ip, intermediate_ip, proxy1_ip, proxy2_ip
        # Logic: Remove last 2 IPs (proxies), take rightmost of what's left
        mock_req.env['HTTP_X_FORWARDED_FOR'] = '203.0.113.0, 198.51.100.0, 192.0.2.0, 198.18.0.0'
        result = test_instance.send(:extract_ip_from_header, 'X-Forwarded-For', 2)
        expect(result).to eq('198.51.100.0')
      end
    end

    context 'with chain shorter than trusted_proxy_depth' do
      it 'returns first IP when chain is shorter than expected' do
        # Chain has only 2 IPs but we expect 3 proxies
        mock_req.env['HTTP_X_FORWARDED_FOR'] = '203.0.113.0, 198.51.100.0'
        result = test_instance.send(:extract_ip_from_header, 'X-Forwarded-For', 3)
        expect(result).to eq('203.0.113.0')
      end
    end

    context 'with RFC 7239 Forwarded header' do
      it 'extracts IP from Forwarded header' do
        mock_req.env['HTTP_FORWARDED'] = 'for=203.0.113.0, for=198.51.100.0'
        result = test_instance.send(:extract_ip_from_header, 'Forwarded', 1)
        expect(result).to eq('203.0.113.0')
      end
    end

    it 'returns nil when no header is present' do
      result = test_instance.send(:extract_ip_from_header, 'X-Forwarded-For', 1)
      expect(result).to be_nil
    end
  end

  describe '#extract_client_ip_for_homepage' do
    let(:mock_req) { double('request', env: {'REMOTE_ADDR' => '203.0.113.0'}) }

    before do
      test_instance.req = mock_req
      allow(OT).to receive(:ld)
    end

    context 'with trusted_proxy_depth of 0' do
      it 'ignores headers and uses REMOTE_ADDR' do
        mock_req.env['HTTP_X_FORWARDED_FOR'] = '198.51.100.0'
        config = {trusted_proxy_depth: 0}
        result = test_instance.send(:extract_client_ip_for_homepage, config)
        expect(result).to eq('203.0.113.0')
      end
    end

    context 'with trusted_proxy_depth > 0' do
      it 'extracts IP from X-Forwarded-For header' do
        mock_req.env['HTTP_X_FORWARDED_FOR'] = '198.51.100.0, 203.0.113.0'
        config = {trusted_proxy_depth: 1, trusted_ip_header: 'X-Forwarded-For'}
        result = test_instance.send(:extract_client_ip_for_homepage, config)
        expect(result).to eq('198.51.100.0')
      end

      it 'falls back to REMOTE_ADDR if extracted IP is private' do
        mock_req.env['HTTP_X_FORWARDED_FOR'] = '10.0.0.1, 203.0.113.0'  # Private IP
        config = {trusted_proxy_depth: 1, trusted_ip_header: 'X-Forwarded-For'}
        result = test_instance.send(:extract_client_ip_for_homepage, config)
        expect(result).to eq('203.0.113.0')  # Falls back to REMOTE_ADDR
      end

      it 'falls back to REMOTE_ADDR if no header is present' do
        config = {trusted_proxy_depth: 1, trusted_ip_header: 'X-Forwarded-For'}
        result = test_instance.send(:extract_client_ip_for_homepage, config)
        expect(result).to eq('203.0.113.0')
      end
    end

    context 'with default configuration' do
      it 'defaults to trusted_proxy_depth of 1' do
        mock_req.env['HTTP_X_FORWARDED_FOR'] = '198.51.100.0, 203.0.113.0'
        config = {}
        result = test_instance.send(:extract_client_ip_for_homepage, config)
        expect(result).to eq('198.51.100.0')
      end

      it 'defaults to X-Forwarded-For header' do
        mock_req.env['HTTP_X_FORWARDED_FOR'] = '198.51.100.0'
        config = {trusted_proxy_depth: 1}
        result = test_instance.send(:extract_client_ip_for_homepage, config)
        expect(result).to eq('198.51.100.0')
      end
    end
  end

  describe '#ip_matches_homepage_cidrs?' do
    before do
      test_instance.instance_variable_set(:@cidr_matchers, [
        IPAddr.new('10.0.0.0/8'),
        IPAddr.new('192.168.1.0/24'),
        IPAddr.new('2001:db8::/32')
      ])
      allow(OT).to receive(:le)
    end

    context 'with matching IPs' do
      it 'matches IP in first CIDR range' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, '10.1.2.3')).to be true
      end

      it 'matches IP in second CIDR range' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, '192.168.1.100')).to be true
      end

      it 'matches IPv6 address in CIDR range' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, '2001:db8::1')).to be true
      end

      it 'matches IP at the edge of CIDR range' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, '192.168.1.1')).to be true
        expect(test_instance.send(:ip_matches_homepage_cidrs?, '192.168.1.254')).to be true
      end
    end

    context 'with non-matching IPs' do
      it 'does not match IP outside all CIDR ranges' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, '203.0.113.0')).to be false
      end

      it 'does not match IP just outside CIDR range' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, '192.168.2.1')).to be false
      end

      it 'does not match IPv6 address outside CIDR range' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, '2001:db9::1')).to be false
      end
    end

    context 'with invalid inputs' do
      it 'returns false for empty string' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, '')).to be false
      end

      it 'returns false for nil' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, nil)).to be false
      end

      it 'returns false for invalid IP address' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, 'not-an-ip')).to be false
      end
    end

    context 'with empty CIDR matchers' do
      before do
        test_instance.instance_variable_set(:@cidr_matchers, [])
      end

      it 'returns false when no CIDRs are configured' do
        expect(test_instance.send(:ip_matches_homepage_cidrs?, '10.1.2.3')).to be false
      end
    end
  end

  describe '#header_matches_mode?' do
    let(:mock_req) { double('request', env: {}) }

    before do
      test_instance.req = mock_req
    end

    context 'with matching header' do
      it 'matches when header value equals expected mode' do
        mock_req.env['HTTP_O_HOMEPAGE_MODE'] = 'internal'
        result = test_instance.send(:header_matches_mode?, 'O-Homepage-Mode', 'internal')
        expect(result).to be true
      end

      it 'handles header with HTTP_ prefix already present' do
        mock_req.env['HTTP_X_CUSTOM_MODE'] = 'external'
        result = test_instance.send(:header_matches_mode?, 'HTTP_X_CUSTOM_MODE', 'external')
        expect(result).to be true
      end

      it 'converts dashes to underscores in header name' do
        mock_req.env['HTTP_X_CUSTOM_HOMEPAGE_MODE'] = 'internal'
        result = test_instance.send(:header_matches_mode?, 'X-Custom-Homepage-Mode', 'internal')
        expect(result).to be true
      end
    end

    context 'with non-matching header' do
      it 'returns false when header value differs from expected mode' do
        mock_req.env['HTTP_O_HOMEPAGE_MODE'] = 'external'
        result = test_instance.send(:header_matches_mode?, 'O-Homepage-Mode', 'internal')
        expect(result).to be false
      end

      it 'returns false when header is not present' do
        result = test_instance.send(:header_matches_mode?, 'O-Homepage-Mode', 'internal')
        expect(result).to be false
      end

      it 'returns false when header is empty' do
        mock_req.env['HTTP_O_HOMEPAGE_MODE'] = ''
        result = test_instance.send(:header_matches_mode?, 'O-Homepage-Mode', 'internal')
        expect(result).to be false
      end
    end

    context 'with invalid inputs' do
      it 'returns false when header_name is nil' do
        result = test_instance.send(:header_matches_mode?, nil, 'internal')
        expect(result).to be false
      end

      it 'returns false when header_name is empty' do
        result = test_instance.send(:header_matches_mode?, '', 'internal')
        expect(result).to be false
      end
    end
  end

  describe 'integration with determine_homepage_mode' do
    before do
      allow(OT).to receive(:info)
      allow(OT).to receive(:ld)
    end

    context 'with CIDR matching (priority 1)' do
      let(:mock_req) do
        double('request', env: {
          'REMOTE_ADDR' => '10.105.64.100',
          'HTTP_X_FORWARDED_FOR' => nil
        })
      end

      before do
        test_instance.req = mock_req
      end

      it 'returns internal mode when client IP matches configured CIDR' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: ['10.105.64.0/20'], # From the bug report - now fixed!
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to eq('internal')
      end

      it 'returns external mode when client IP matches configured CIDR' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'external',
                  matching_cidrs: ['10.105.64.0/20'],
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to eq('external')
      end

      it 'returns nil when client IP does not match any CIDR' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: ['192.168.1.0/24'], # Different range
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to be_nil
      end

      it 'matches against multiple configured CIDRs' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: [
                    '192.168.1.0/24',    # Does not match
                    '10.105.64.0/20',    # Matches!
                    '172.16.0.0/16'      # Does not match
                  ],
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to eq('internal')
      end
    end

    context 'with header matching (priority 2 - fallback)' do
      let(:mock_req) do
        double('request', env: {
          'REMOTE_ADDR' => '203.0.113.0',  # Public IP not in CIDR
          'HTTP_O_HOMEPAGE_MODE' => 'internal'
        })
      end

      before do
        test_instance.req = mock_req
      end

      it 'falls back to header when CIDR does not match' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: ['10.0.0.0/8'],        # Does not match
                  mode_header: 'O-Homepage-Mode'
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to eq('internal')
      end

      it 'returns nil when header does not match expected mode' do
        mock_req.env['HTTP_O_HOMEPAGE_MODE'] = 'external'  # Header says external
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',  # Config expects internal
                  matching_cidrs: ['10.0.0.0/8'],
                  mode_header: 'O-Homepage-Mode'
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to be_nil
      end
    end

    context 'with CIDR priority over header' do
      let(:mock_req) do
        double('request', env: {
          'REMOTE_ADDR' => '10.105.64.100',
          'HTTP_O_HOMEPAGE_MODE' => 'external'  # Header says external
        })
      end

      before do
        test_instance.req = mock_req
      end

      it 'CIDR match takes priority over header' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: ['10.105.64.0/20'],  # IP matches this
                  mode_header: 'O-Homepage-Mode'
                }
              }
            }
          }
        })

        # Even though header says 'external', CIDR match should win
        mode = test_instance.determine_homepage_mode
        expect(mode).to eq('internal')
      end
    end

    context 'with proxy configuration' do
      let(:mock_req) do
        double('request', env: {
          'REMOTE_ADDR' => '198.51.100.0',  # Proxy IP
          'HTTP_X_FORWARDED_FOR' => '203.0.113.0, 198.51.100.0'  # Public Client IP, Proxy
        })
      end

      before do
        test_instance.req = mock_req
      end

      it 'extracts client IP from X-Forwarded-For and matches CIDR' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: ['203.0.113.0/24'],  # Public IP range
                  trusted_proxy_depth: 1,
                  trusted_ip_header: 'X-Forwarded-For'
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to eq('internal')
      end

      it 'rejects private IP from header and falls back to REMOTE_ADDR' do
        # Client sends private IP in header (spoofing attempt or misconfiguration)
        mock_req.env['HTTP_X_FORWARDED_FOR'] = '10.0.0.1, 198.51.100.0'

        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: ['198.51.100.0/24'],  # Proxy IP range
                  trusted_proxy_depth: 1,
                  trusted_ip_header: 'X-Forwarded-For'
                }
              }
            }
          }
        })

        # Private IP is rejected, falls back to REMOTE_ADDR which matches
        mode = test_instance.determine_homepage_mode
        expect(mode).to eq('internal')
      end

      it 'ignores headers when trusted_proxy_depth is 0' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: ['198.51.100.0/24'],  # Proxy IP range
                  trusted_proxy_depth: 0  # Don't trust headers
                }
              }
            }
          }
        })

        # Should match using REMOTE_ADDR (proxy IP)
        mode = test_instance.determine_homepage_mode
        expect(mode).to eq('internal')
      end
    end

    context 'with invalid configuration' do
      let(:mock_req) do
        double('request', env: {
          'REMOTE_ADDR' => '10.105.64.100'
        })
      end

      before do
        test_instance.req = mock_req
      end

      it 'returns nil when mode is not internal or external' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'invalid-mode',
                  matching_cidrs: ['10.105.64.0/20']
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to be_nil
      end

      it 'returns nil when homepage config is missing' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {}
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to be_nil
      end

      it 'returns nil when ui config is missing' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {}
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to be_nil
      end

      it 'returns nil when mode is nil' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: nil,
                  matching_cidrs: ['10.105.64.0/20']
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to be_nil
      end
    end

    context 'with no matches' do
      let(:mock_req) do
        double('request', env: {
          'REMOTE_ADDR' => '203.0.113.0'  # Public IP not in CIDR
        })
      end

      before do
        test_instance.req = mock_req
      end

      it 'returns nil when neither CIDR nor header match' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: ['10.0.0.0/8'],
                  mode_header: 'O-Homepage-Mode'
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to be_nil
      end
    end

    context 'with privacy-violating narrow CIDRs (after fix)' do
      let(:mock_req) do
        double('request', env: {
          'REMOTE_ADDR' => '192.168.1.1'
        })
      end

      before do
        test_instance.req = mock_req
      end

      it 'rejects narrow /32 CIDR and returns nil' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: ['192.168.1.1/32']  # Single host - privacy violation
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to be_nil  # CIDR rejected, no match
      end

      it 'rejects narrow /28 CIDR and returns nil' do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              ui: {
                homepage: {
                  mode: 'internal',
                  matching_cidrs: ['192.168.1.0/28']  # Only 14 IPs - privacy violation
                }
              }
            }
          }
        })

        mode = test_instance.determine_homepage_mode
        expect(mode).to be_nil
      end
    end

    context 'with default_mode configuration' do
      let(:mock_req) do
        double('request', env: {
          'REMOTE_ADDR' => '203.0.113.50'  # Public IP that doesn't match any CIDR
        })
      end

      before do
        test_instance.req = mock_req
      end

      context 'when IP does not match CIDR and default_mode is external' do
        it 'returns the default_mode value' do
          allow(OT).to receive(:conf).and_return({
            site: {
              interface: {
                ui: {
                  homepage: {
                    mode: 'internal',
                    matching_cidrs: ['10.0.0.0/8', '192.168.0.0/16'],
                    default_mode: 'external'
                  }
                }
              }
            }
          })

          mode = test_instance.determine_homepage_mode
          expect(mode).to eq('external')
        end
      end

      context 'when IP does not match CIDR and default_mode is internal' do
        it 'returns the default_mode value' do
          allow(OT).to receive(:conf).and_return({
            site: {
              interface: {
                ui: {
                  homepage: {
                    mode: 'external',
                    matching_cidrs: ['10.0.0.0/8'],
                    default_mode: 'internal'
                  }
                }
              }
            }
          })

          mode = test_instance.determine_homepage_mode
          expect(mode).to eq('internal')
        end
      end

      context 'when IP matches CIDR, default_mode is ignored' do
        let(:mock_req) do
          double('request', env: {
            'REMOTE_ADDR' => '10.0.0.100'  # Matches 10.0.0.0/8
          })
        end

        it 'returns the configured mode, not the default_mode' do
          allow(OT).to receive(:conf).and_return({
            site: {
              interface: {
                ui: {
                  homepage: {
                    mode: 'internal',
                    matching_cidrs: ['10.0.0.0/8'],
                    default_mode: 'external'
                  }
                }
              }
            }
          })

          mode = test_instance.determine_homepage_mode
          expect(mode).to eq('internal')
        end
      end

      context 'when default_mode is not set' do
        it 'returns nil (backward compatible)' do
          allow(OT).to receive(:conf).and_return({
            site: {
              interface: {
                ui: {
                  homepage: {
                    mode: 'internal',
                    matching_cidrs: ['10.0.0.0/8']
                    # default_mode not set
                  }
                }
              }
            }
          })

          mode = test_instance.determine_homepage_mode
          expect(mode).to be_nil
        end
      end

      context 'when default_mode has an invalid value' do
        it 'returns nil and ignores invalid default_mode' do
          allow(OT).to receive(:conf).and_return({
            site: {
              interface: {
                ui: {
                  homepage: {
                    mode: 'internal',
                    matching_cidrs: ['10.0.0.0/8'],
                    default_mode: 'invalid_mode'
                  }
                }
              }
            }
          })

          mode = test_instance.determine_homepage_mode
          expect(mode).to be_nil
        end
      end

      context 'when header matches but IP does not, and default_mode is set' do
        let(:mock_req) do
          double('request', env: {
            'REMOTE_ADDR' => '203.0.113.50',
            'HTTP_O_HOMEPAGE_MODE' => 'internal'
          })
        end

        it 'returns the configured mode from header, not default_mode' do
          allow(OT).to receive(:conf).and_return({
            site: {
              interface: {
                ui: {
                  homepage: {
                    mode: 'internal',
                    matching_cidrs: ['10.0.0.0/8'],
                    mode_header: 'O-Homepage-Mode',
                    default_mode: 'external'
                  }
                }
              }
            }
          })

          mode = test_instance.determine_homepage_mode
          expect(mode).to eq('internal')  # Header match takes priority over default_mode
        end
      end

      context 'real-world scenario: office network with external default' do
        it 'applies internal mode for office IPs' do
          mock_req_office = double('request', env: {
            'REMOTE_ADDR' => '203.0.113.10'  # Office IP
          })
          test_instance.req = mock_req_office

          allow(OT).to receive(:conf).and_return({
            site: {
              interface: {
                ui: {
                  homepage: {
                    mode: 'internal',
                    matching_cidrs: ['203.0.113.0/24'],  # Office network
                    default_mode: 'external'
                  }
                }
              }
            }
          })

          mode = test_instance.determine_homepage_mode
          expect(mode).to eq('internal')
        end

        it 'applies external mode for public IPs' do
          mock_req_public = double('request', env: {
            'REMOTE_ADDR' => '198.51.100.50'  # Public IP outside office
          })
          test_instance.req = mock_req_public

          allow(OT).to receive(:conf).and_return({
            site: {
              interface: {
                ui: {
                  homepage: {
                    mode: 'internal',
                    matching_cidrs: ['203.0.113.0/24'],  # Office network
                    default_mode: 'external'
                  }
                }
              }
            }
          })

          mode = test_instance.determine_homepage_mode
          expect(mode).to eq('external')
        end
      end
    end
  end
end
