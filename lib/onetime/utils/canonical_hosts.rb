# lib/onetime/utils/canonical_hosts.rb
#
# frozen_string_literal: true

require_relative 'domain_parser'

module Onetime
  module Utils
    # Single derivation point for the deployment's canonical host set.
    #
    # The set contains up to N hosts read from config:
    #
    #   features.domains.default      - the default/link domain (ANCHOR)
    #   site.host                     - the display/app host    (ANCHOR)
    #   features.domains.link_domains - the operator link pool  (#4063)
    #
    # Ordering contract: the PRIMARY host comes FIRST. When
    # features.domains.default is present it IS the primary canonical
    # domain (#3841); site.host follows as the secondary anchor; link
    # domains are appended after both. Consumers that need "the" canonical
    # host must take element 0 (or `primary`), never re-derive their own
    # ordering from config.
    #
    # Two distinct sets come out of here and they are NOT interchangeable:
    #
    #   hosts / normalized_hosts        - classification and admission. Link
    #                                     domains are members, so a request
    #                                     to an operator link domain
    #                                     classifies :canonical instead of
    #                                     falling through to :invalid.
    #   anchor_hosts / normalized_...   - the pre-#4063 two-element set. This
    #                                     is what ANCHORS generated links
    #                                     (CustomDomain.default_domain?). A
    #                                     link-pool host must never land here:
    #                                     process_share_domain returns early
    #                                     on a default domain, so a pool
    #                                     member in this set would silently
    #                                     discard every picker selection and
    #                                     re-anchor links on the host the
    #                                     operator meant to hide.
    #
    # link_domains is therefore classification-only: it widens what the
    # deployment will serve and what the picker offers (`link_pool`), never
    # what a link defaults to.
    #
    # Behavior is UNCHANGED when features.domains.link_domains is nil: the
    # canonical set is the same two anchors in the same order, and
    # `link_pool` is [primary].
    #
    # Both the DomainStrategy middleware and the CustomDomain model build
    # their canonical sets here so request classification, registration
    # guards, and share_domain filtering can never disagree about which
    # hosts are canonical.
    module CanonicalHosts
      class << self
        # Canonical hosts as configured (whitespace-trimmed only), primary
        # first, link-pool members last. Suitable for display; use
        # normalized_hosts or canonical_host? for comparisons.
        #
        # @param default_host [String, nil] Override for features.domains.default
        # @param site_host [String, nil] Override for site.host
        # @param link_hosts [Array<String>, String, nil] Override for
        #   features.domains.link_domains
        # @return [Array<String>]
        def hosts(default_host: config_default_host, site_host: config_site_host,
                  link_hosts: config_link_hosts)
          ([default_host, site_host] + Array(link_hosts))
            .map { |host| host.to_s.strip }.reject(&:empty?).uniq
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

        # The link-ANCHOR host set: features.domains.default and site.host
        # only, primary first. Never contains a link-pool member.
        #
        # This is the authority for "does this host anchor generated links"
        # (CustomDomain.default_domain?). Extra keyword arguments (notably
        # link_hosts:) are accepted and ignored so callers can forward the
        # same kwargs they pass to hosts/normalized_hosts.
        #
        # @return [Array<String>]
        def anchor_hosts(default_host: config_default_host, site_host: config_site_host, **)
          hosts(default_host: default_host, site_host: site_host, link_hosts: nil)
        end

        # Anchor hosts normalized for comparison, primary first.
        #
        # @return [Array<String>]
        def normalized_anchor_hosts(**)
          anchor_hosts(**).filter_map { |host| DomainParser.extract_hostname(host) }.uniq
        end

        # The hosts offered in the domain-context picker (#4063).
        #
        # Three-way semantics, and the nil-vs-[] distinction is the whole
        # feature — do not collapse it:
        #
        #   nil (unset)     - the operator said nothing; offer [primary].
        #   ['a.com', ...]  - offer exactly those, in that order.
        #   [] (set-empty)  - returned faithfully as []. Onetime::Config
        #                     raises at boot for this case; it must not be
        #                     silently rewritten to [primary] here.
        #
        # @param link_hosts [Array<String>, String, nil] Override for
        #   features.domains.link_domains
        # @return [Array<String>]
        def link_pool(link_hosts: config_link_hosts, **)
          return anchor_hosts(**).first(1) if link_hosts.nil?

          Array(link_hosts).map { |host| host.to_s.strip }.reject(&:empty?).uniq
        end

        private

        def config_default_host
          OT.conf&.dig('features', 'domains', 'default')
        end

        def config_link_hosts
          OT.conf&.dig('features', 'domains', 'link_domains')
        end

        def config_site_host
          OT.conf&.dig('site', 'host')
        end
      end
    end
  end
end
