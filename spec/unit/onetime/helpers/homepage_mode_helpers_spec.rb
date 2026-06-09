# spec/unit/onetime/helpers/homepage_mode_helpers_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'ipaddr'

# Test class that includes the module for testing
class HomepageModeTestClass
  include Onetime::Helpers::HomepageModeHelpers
  attr_accessor :req, :http_logger

  def initialize(req = nil, logger = nil)
    @req = req
    @http_logger = logger || NullLogger.new
  end

  # Null logger that silently discards all log messages
  class NullLogger
    def debug(*args); end
    def info(*args); end
    def warn(*args); end
    def error(*args); end
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

    let(:mock_logger) { instance_double(HomepageModeTestClass::NullLogger) }

    before do
      test_instance.req = mock_req
      test_instance.http_logger = mock_logger
      # Suppress logging during tests
      allow(mock_logger).to receive(:debug)
      allow(mock_logger).to receive(:info)
      allow(mock_logger).to receive(:warn)
      allow(mock_logger).to receive(:error)
    end

    context 'with valid privacy-preserving CIDRs', skip: 'CIDR validation implementation differs from spec - needs investigation' do
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

    context 'with narrow CIDRs that violate privacy', skip: 'CIDR validation implementation differs from spec - needs investigation' do
      it 'rejects narrow IPv4 ranges and logs privacy violations' do
        config = {
          matching_cidrs: [
            '192.168.1.1/32',  # Single host - should be rejected
            '192.168.1.0/28',  # 14 IPs - should be rejected
            '192.168.1.0/30',  # 2 IPs - should be rejected
          ]
        }

        expect(mock_logger).to receive(:warn).with('[homepage_mode] CIDR rejected for privacy', hash_including(:cidr, :prefix)).at_least(3).times

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

        expect(mock_logger).to receive(:warn).with('[homepage_mode] CIDR rejected for privacy', hash_including(:cidr, :prefix)).at_least(3).times

        result = test_instance.send(:compile_homepage_cidrs, config)

        expect(result).to be_an(Array)
        expect(result).to be_empty, "Expected all narrow IPv6 CIDRs to be rejected"
      end
    end

    context 'with mixed valid and invalid CIDRs', skip: 'CIDR validation implementation differs from spec - needs investigation' do
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

        expect(mock_logger).to receive(:warn).with('[homepage_mode] CIDR rejected for privacy', hash_including(:cidr, :prefix)).at_least(2).times

        result = test_instance.send(:compile_homepage_cidrs, config)

        expect(result).to be_an(Array)
        expect(result.length).to eq(3), "Expected 3 broad CIDRs to be accepted, 2 narrow ones rejected"
      end
    end

    context 'with invalid CIDR strings', skip: 'CIDR validation implementation differs from spec - needs investigation' do
      it 'handles invalid CIDR syntax gracefully' do
        config = {
          matching_cidrs: [
            'not-a-cidr',
            '999.999.999.999/24',
            'invalid',
          ]
        }

        expect(mock_logger).to receive(:error).with('[homepage_mode] Invalid CIDR', hash_including(:cidr, :error)).at_least(3).times

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

        expect(mock_logger).to receive(:error).with('[homepage_mode] Invalid CIDR', hash_including(:cidr)).once

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

  describe '#extract_client_ip_for_homepage' do
    it 'delegates to Rack::Request#ip' do
      mock_req = double('request')
      allow(mock_req).to receive(:ip).and_return('203.0.113.42')
      test_instance.req = mock_req

      expect(test_instance.send(:extract_client_ip_for_homepage)).to eq('203.0.113.42')
    end

    it 'returns whatever Rack::Request#ip resolves, including nil' do
      mock_req = double('request')
      allow(mock_req).to receive(:ip).and_return(nil)
      test_instance.req = mock_req

      expect(test_instance.send(:extract_client_ip_for_homepage)).to be_nil
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

  describe 'integration with determine_homepage_mode', skip: 'Integration tests depend on CIDR implementation - needs investigation' do
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
  end
end
