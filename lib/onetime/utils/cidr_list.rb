# lib/onetime/utils/cidr_list.rb
#
# frozen_string_literal: true

require 'ipaddr'

module Onetime
  module Utils
    # Operator-supplied CIDR lists: normalization at write time and the
    # allow/deny verdict at request time.
    #
    # Shared by the per-domain homepage network rules
    # (CustomDomain::HomepageConfig#allowed_cidrs / #denied_cidrs). Pure:
    # no I/O, no logging, no knowledge of where the lists are stored. The
    # model owns persistence and failure logging; this module owns the two
    # judgments that must agree exactly between the write path (what is
    # accepted into a list) and the read path (what a stored list means).
    #
    # ## Normalization
    #
    # Every entry is parsed with IPAddr and re-emitted as `address/prefix`
    # (a bare address becomes a /32 or /128). Host bits below the prefix are
    # dropped, so "10.1.2.3/8" is stored as "10.0.0.0/8". Duplicates (after
    # normalization) collapse to the first occurrence; order is otherwise
    # preserved. Entries that do not parse raise {InvalidEntry}; lists with
    # more than {MAX_ENTRIES} distinct ranges raise {TooManyEntries}. Both
    # are ArgumentError subclasses carrying the offending input so a caller
    # can report it against its field.
    #
    # ## Verdict
    #
    # {permitted?} is judged exclusively through the `env['otto.ip_match']`
    # verdict-only closure that IPPrivacyMiddleware installs over the
    # resolved, PRE-MASK client IP (see docs/specs/domain-ip-allowlist).
    # `env['otto.client_ip']` and `req.ip` are privacy-masked (/24, /48) and
    # would misjudge any finer range in both directions, so this module never
    # accepts an IP string. Deny wins over allow; an empty allow list means
    # "everyone not denied"; two empty lists mean no restriction at all.
    module CidrList
      # Cap per list. Comparable SaaS allowlists sit in the 100-500 range
      # (GitHub, Okta, Atlassian); 100 keeps per-request parsing trivially
      # cheap and can be raised later without a data migration.
      MAX_ENTRIES = 100

      # Every address, both families. Used as a resolvability probe: the
      # otto.ip_match closure answers false for a request with no resolvable
      # client IP, which is indistinguishable from "outside every range" —
      # except that no resolvable IP is also outside THESE ranges, while any
      # real address is inside one of them.
      UNIVERSAL = [IPAddr.new('0.0.0.0/0'), IPAddr.new('::/0')].freeze

      # An entry that does not parse as an IPv4/IPv6 address or CIDR range.
      class InvalidEntry < ArgumentError
        attr_reader :entry

        def initialize(entry, reason = nil)
          @entry = entry.to_s
          super(reason ? "Invalid CIDR: #{@entry} (#{reason})" : "Invalid CIDR: #{@entry}")
        end
      end

      # More distinct ranges than {MAX_ENTRIES}.
      class TooManyEntries < ArgumentError
        attr_reader :count, :max

        def initialize(count, max = MAX_ENTRIES)
          @count = count
          @max   = max
          super("Too many CIDR entries: #{count} (maximum #{max})")
        end
      end

      module_function

      # Canonical `address/prefix` form of one entry.
      #
      # @param entry [#to_s] an IP address or CIDR range
      # @return [String]
      # @raise [InvalidEntry] when the entry does not parse
      def canonical(entry)
        raw = entry.to_s.strip
        raise InvalidEntry.new(raw, 'blank') if raw.empty?
        # IPAddr accepts an IPv6 zone id ("fe80::1%eth0"), which names an
        # interface on the parsing host and has no meaning in a network rule.
        raise InvalidEntry.new(raw, 'zone id not allowed') if raw.include?('%')

        addr = IPAddr.new(raw)
        "#{addr}/#{addr.prefix}"
      rescue IPAddr::Error => ex
        raise InvalidEntry.new(raw, ex.message)
      end

      # Normalize a list for storage: canonical form, de-duplicated,
      # order-preserving, capped.
      #
      # @param entries [Array<#to_s>, nil]
      # @return [Array<String>]
      # @raise [InvalidEntry, TooManyEntries]
      def normalize(entries)
        normalized = Array(entries).map { canonical(it) }.uniq
        raise TooManyEntries.new(normalized.length) if normalized.length > MAX_ENTRIES

        normalized
      end

      # Parse stored entries into IPAddr ranges for matching.
      #
      # Strict on purpose: a stored entry that does not parse raises rather
      # than being skipped, because silently dropping an entry narrows an
      # allow list or widens a deny list. Callers treat the raise as a
      # fail-closed verdict.
      #
      # @param entries [Array<String>]
      # @return [Array<IPAddr>]
      # @raise [IPAddr::Error]
      def parse(entries)
        Array(entries).map { IPAddr.new(it.to_s.strip) }
      end

      # The allow/deny verdict for one request.
      #
      # @param ip_match [#call, nil] the env['otto.ip_match'] closure; called
      #   with an Array<IPAddr> and expected to answer true/false
      # @param allowed [Array<String, IPAddr>] ranges that may use the surface
      #   (empty = everyone not denied)
      # @param denied [Array<String, IPAddr>] ranges that may never use it
      # @return [Boolean] true when no rules exist, or when the client is in
      #   no denied range and (if any are configured) in an allowed range.
      #   false when rules exist but there is no usable matcher, no
      #   resolvable client IP, a deny match, or an allow miss.
      # @raise [IPAddr::Error] when a configured entry does not parse
      def permitted?(ip_match, allowed: [], denied: [])
        allowed_ranges = allowed.map { it.is_a?(IPAddr) ? it : IPAddr.new(it.to_s.strip) }
        denied_ranges  = denied.map { it.is_a?(IPAddr) ? it : IPAddr.new(it.to_s.strip) }
        return true if allowed_ranges.empty? && denied_ranges.empty?

        return false unless ip_match.respond_to?(:call)
        return false unless ip_match.call(UNIVERSAL) == true
        return false if denied_ranges.any? && ip_match.call(denied_ranges) == true
        return true if allowed_ranges.empty?

        ip_match.call(allowed_ranges) == true
      end
    end
  end
end
