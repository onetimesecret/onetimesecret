# lib/onetime/utils/domain_parser.rb
#
# frozen_string_literal: true

require 'public_suffix'
require 'uri'

module Onetime
  module Utils
    # Centralized hostname parsing and comparison utilities.
    #
    # Provides secure hostname validation methods that properly respect
    # domain boundaries using the PublicSuffix gem. This prevents security
    # issues like matching `attacker-example.com` when checking for `example.com`.
    #
    # @example Exact hostname comparison
    #   DomainParser.hostname_matches?('example.com', 'example.com')     # => true
    #   DomainParser.hostname_matches?('EXAMPLE.COM:443', 'example.com') # => true
    #   DomainParser.hostname_matches?('sub.example.com', 'example.com') # => false
    #
    # @example Subdomain checking
    #   DomainParser.hostname_within_domain?('sub.example.com', 'example.com')      # => true
    #   DomainParser.hostname_within_domain?('attacker-example.com', 'example.com') # => false
    #
    module DomainParser
      # Maximum allowed hostname length (per RFC 1035)
      MAX_HOSTNAME_LENGTH = 253

      # Maximum allowed subdomain depth to prevent abuse
      MAX_SUBDOMAIN_DEPTH = 10

      class << self
        # Extracts and normalizes a hostname from various input formats.
        #
        # Handles URI objects, URL strings, and plain hostnames. Strips ports
        # and normalizes to lowercase.
        #
        # @param input [String, URI, nil] The input to extract hostname from
        # @return [String, nil] Normalized hostname or nil if extraction fails
        #
        # @example
        #   extract_hostname('https://Example.COM:443/path') # => 'example.com'
        #   extract_hostname('Example.COM:8080')            # => 'example.com'
        #   extract_hostname(URI('https://foo.bar'))        # => 'foo.bar'
        #   extract_hostname(nil)                           # => nil
        #
        def extract_hostname(input)
          return nil if input.nil?

          host = case input
                 when URI
                   input.host
                 when String
                   extract_from_string(input)
                 else
                   input.to_s
                 end

          normalize_hostname(host)
        end

        # Compares two hostnames for exact equality.
        #
        # Comparison is case-insensitive and ignores ports. Does NOT match
        # subdomains - use {#hostname_within_domain?} for that.
        #
        # @param left [String, URI, nil] First hostname to compare
        # @param right [String, URI, nil] Second hostname to compare
        # @return [Boolean] true if hostnames match exactly
        #
        # @example
        #   hostname_matches?('example.com', 'example.com')           # => true
        #   hostname_matches?('EXAMPLE.COM', 'example.com')           # => true
        #   hostname_matches?('example.com:443', 'example.com')       # => true
        #   hostname_matches?('sub.example.com', 'example.com')       # => false
        #   hostname_matches?('attacker-example.com', 'example.com')  # => false
        #
        def hostname_matches?(left, right)
          left_host  = extract_hostname(left)
          right_host = extract_hostname(right)

          return false if left_host.nil? || right_host.nil?

          left_host == right_host
        end

        # Checks if a hostname equals or is a subdomain of a domain.
        #
        # Uses PublicSuffix for proper domain boundary detection. This ensures
        # that `attacker-example.com` is NOT considered within `example.com`.
        #
        # @param hostname [String, URI, nil] The hostname to check
        # @param domain [String, URI, nil] The domain to check against
        # @return [Boolean] true if hostname equals or is subdomain of domain
        #
        # @example
        #   hostname_within_domain?('example.com', 'example.com')              # => true
        #   hostname_within_domain?('sub.example.com', 'example.com')          # => true
        #   hostname_within_domain?('deep.sub.example.com', 'example.com')     # => true
        #   hostname_within_domain?('attacker-example.com', 'example.com')     # => false
        #   hostname_within_domain?('example.com.attacker.com', 'example.com') # => false
        #
        # @security This method is designed for SSRF prevention in webhook validation.
        #   When PublicSuffix cannot parse a domain (unknown TLDs like .local, .corp),
        #   it falls back to a strict anchored regex that blocks all known attack vectors:
        #   - Suffix attacks: "attacker-example.com" (no dot before target)
        #   - Prefix attacks: "example.com.evil.com" (doesn't end with target)
        #   - Empty subdomain: ".example.com" (regex requires ≥1 char before dot)
        #   - Injection attacks: newlines, null bytes (blocked by \A \z anchors)
        #
        def hostname_within_domain?(hostname, domain)
          host   = extract_hostname(hostname)
          target = extract_hostname(domain)

          return false if host.nil? || target.nil?
          return true if host == target

          # Parse both using PublicSuffix to get proper domain boundaries
          begin
            host_parsed   = PublicSuffix.parse(host, default_rule: nil)
            target_parsed = PublicSuffix.parse(target, default_rule: nil)

            # Check if registrable domains match (e.g., both are "example.com")
            return false unless host_parsed.domain == target_parsed.domain

            # If domains match, host is either equal or a subdomain
            # The host must end with the target (as a proper suffix with dot boundary)
            host == target || host.end_with?(".#{target}")
          rescue PublicSuffix::Error
            # Fallback for unknown TLDs (.local, .corp, .internal) or malformed domains.
            # Regex is secure: \A (true start) and \z (true end) prevent injection,
            # .+ requires ≥1 char before dot, Regexp.escape prevents regex injection.
            # Only theoretical gap: TLD boundaries (e.g., example.co.uk vs co.uk),
            # but that requires attacker to control the TARGET, not the input.
            host.match?(/\A.+\.#{Regexp.escape(target)}\z/)
          end
        end

        # Validates basic hostname format.
        #
        # Checks for valid characters, length limits, and structure without
        # requiring DNS resolution or TLD validation.
        #
        # @param input [String, nil] The hostname to validate
        # @return [Boolean] true if hostname has valid format
        #
        # @example
        #   basically_valid?('example.com')     # => true
        #   basically_valid?('sub.example.com') # => true
        #   basically_valid?('localhost')       # => true
        #   basically_valid?('')                # => false
        #   basically_valid?('exam ple.com')    # => false (space)
        #   basically_valid?('a' * 300)         # => false (too long)
        #
        def basically_valid?(input)
          return false if input.nil?

          host = input.to_s.strip
          return false if host.empty?
          return false if host.length > MAX_HOSTNAME_LENGTH

          # Only alphanumeric, dots, and hyphens are valid in hostnames
          return false unless host.match?(/\A[a-zA-Z0-9.-]+\z/)

          # Check segment constraints
          segments = host.split('.').reject(&:empty?)
          return false if segments.empty?
          return false if segments.length > MAX_SUBDOMAIN_DEPTH

          # Each segment must not start or end with hyphen
          segments.all? do |segment|
            !segment.start_with?('-') && !segment.end_with?('-') && segment.length <= 63
          end
        end

        private

        # Extracts hostname from a string (URL or plain hostname).
        #
        # @param str [String] Input string
        # @return [String, nil] Extracted hostname
        def extract_from_string(str)
          str = str.to_s.strip
          return nil if str.empty?

          # If it looks like a URL, only extract via URI parsing - don't guess
          if str.include?('://')
            begin
              uri = URI.parse(str)
              return uri.host # Returns host or nil if no host component
            rescue URI::InvalidURIError
              return nil # Malformed URL, do not attempt to guess
            end
          end

          # Treat as plain hostname, strip port if present
          str.split(':').first
        end

        # Normalizes a hostname (lowercase, strip whitespace).
        #
        # @param host [String, nil] Hostname to normalize
        # @return [String, nil] Normalized hostname
        def normalize_hostname(host)
          return nil if host.nil?

          normalized = host.to_s.strip.downcase
          normalized.empty? ? nil : normalized
        end
      end
    end
  end
end
