# lib/onetime/utils/canonical_hosts.rb
#
# frozen_string_literal: true

require_relative 'domain_parser'

module Onetime
  module Utils
    # Single derivation point for the deployment's canonical host set.
    #
    # The set contains up to two hosts read from config:
    #
    #   features.domains.default - the default/link domain
    #   site.host                - the display/app host
    #
    # Ordering contract: the PRIMARY host comes FIRST. When
    # features.domains.default is present it IS the primary canonical
    # domain (#3841); site.host follows as the secondary anchor. Consumers
    # that need "the" canonical host must take element 0 (or `primary`),
    # never re-derive their own ordering from config.
    #
    # Both the DomainStrategy middleware and the CustomDomain model build
    # their canonical sets here so request classification, registration
    # guards, and share_domain filtering can never disagree about which
    # hosts are canonical.
    module CanonicalHosts
      class << self
        # Canonical hosts as configured (whitespace-trimmed only), primary
        # first. Suitable for display; use normalized_hosts or
        # canonical_host? for comparisons.
        #
        # @param default_host [String, nil] Override for features.domains.default
        # @param site_host [String, nil] Override for site.host
        # @return [Array<String>]
        def hosts(default_host: config_default_host, site_host: config_site_host)
          [default_host, site_host].map { |host| host.to_s.strip }.reject(&:empty?).uniq
        end

        # Canonical hosts normalized for comparison (lowercased, port and
        # scheme stripped via DomainParser), primary first.
        #
        # @return [Array<String>]
        def normalized_hosts(**)
          hosts(**).filter_map { |host| DomainParser.extract_hostname(host) }.uniq
        end

        # The primary canonical host: features.domains.default when
        # present, else site.host.
        #
        # @return [String, nil]
        def primary(**)
          hosts(**).first
        end

        # Exact membership test against the canonical set, normalized on
        # both sides.
        #
        # @param host [String, URI, nil]
        # @return [Boolean]
        def canonical_host?(host, **)
          normalized = DomainParser.extract_hostname(host)
          return false if normalized.nil?

          normalized_hosts(**).include?(normalized)
        end

        private

        def config_default_host
          OT.conf&.dig('features', 'domains', 'default')
        end

        def config_site_host
          OT.conf&.dig('site', 'host')
        end
      end
    end
  end
end
