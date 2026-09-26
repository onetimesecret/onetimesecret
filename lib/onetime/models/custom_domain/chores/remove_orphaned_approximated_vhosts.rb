# lib/onetime/models/custom_domain/chores/remove_orphaned_approximated_vhosts.rb
#
# frozen_string_literal: true

# Housekeeping chore: Delete Approximated virtual hosts that were orphaned
# when the system validation strategy moved off `approximated`, and clear
# the Approximated-era vhost state stored on the CustomDomain record.
#
# Background:
#   Under the `approximated` strategy every custom domain gets a vhost on
#   Approximated's cluster (VerifyDomain / Domains::Create store the API's
#   `data` object verbatim in the `vhost` field). After a cutover the remote
#   vhost keeps existing (billable, and still able to terminate TLS for the
#   hostname if DNS points there). CaddyOnDemandStrategy replaces stale UI
#   fields with its current probe data and marks that blob as still requiring
#   Approximated cleanup. An ordinary `source: tls_probe` blob is not vhost
#   state; one carrying the cleanup marker is.
#
# Deleting a vhost that still serves traffic is a customer outage that we
# cannot undo without re-provisioning and a new certificate. Every guard
# therefore fails closed, and an indeterminate answer never deletes.
#
# Behaviour (idempotent; skips return nil, a cleared record returns true):
#
#   1. no vhost state on the record                    → silent skip
#   2. system strategy is approximated, or not set     → skip (vhost is live)
#   3. no Approximated API key configured              → skip, state kept (it
#                                                        is the only record
#                                                        that a vhost exists)
#   4. stored vhost content is not a JSON object       → warn + skip (corrupt
#                                                        data; which hostname
#                                                        it belongs to cannot
#                                                        be checked, so it
#                                                        needs manual review)
#      stored incoming_address ≠ display_domain        → log + skip (renamed
#                                                        domain; the old name
#                                                        may belong to someone
#                                                        else now)
#   5. no proxy_ip / proxy_host to compare against,
#      or proxy_host does not resolve                  → skip (indeterminate)
#   6. domain has no A/AAAA answer (NXDOMAIN, SERVFAIL
#      and timeout are indistinguishable via Resolv)   → skip (indeterminate)
#   7. domain resolves to the Approximated cluster,
#      or CNAMEs to proxy_host                         → skip (still served)
#   8. DNS has moved, dry run (the default)            → log candidate, skip,
#                                                        no API call
#   9. DNS has moved, apply mode:
#      a. live vhost lookup says not found             → clear state, true
#      b. live vhost is ACTIVE_SSL_PROXIED, resolving,
#         hit by traffic, UNKNOWN or unreadable        → log + skip
#      c. live vhost is idle                           → DELETE; on success or
#                                                        not-found clear state,
#                                                        log, true
#      d. any other API failure                        → raise CleanupFailed
#                                                        (transport errors
#                                                        propagate as-is),
#                                                        state kept, retried
#                                                        on the next run
#
# Why DNS alone is not enough (9b): a host fronted by another proxy (e.g. a
# Cloudflare CNAME setup) resolves to that proxy while its requests still
# reach the Approximated cluster. Approximated reports that case as
# ACTIVE_SSL_PROXIED, so its own view of the vhost has to agree with ours.
#
# Exceptions propagate to HousekeepingJob#run_chores_for, which counts them
# under `errors` and continues with the next record.
#
# Never touched: verified, verified_by_override, resolving, and the TXT
# validation fields. Ownership does not depend on which edge serves the
# domain.
#
# Apply mode is opt-in because HousekeepingJob runs every registered
# CustomDomain chore nightly and the framework has no dry-run or on-demand
# flag. Without the environment variable the chore only reports candidates
# and makes no Approximated API call:
#
#   bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts
#   APPROXIMATED_VHOST_CLEANUP=apply bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts
#
# Keep APPROXIMATED_API_KEY and APPROXIMATED_PROXY_IP / APPROXIMATED_PROXY_HOST
# configured until the chore reports nothing left, then remove this file.

require 'ipaddr'
require 'json'
require 'resolv'

require_relative '../../../domain_validation/features'
require_relative '../../../domain_validation/approximated_client'
require_relative '../../../domain_validation/ascii_hostname'

module Onetime
  module Chores
    # Callable chore (Familia accepts any object responding to #call). Every
    # collaborator is injected so specs never touch the network; the defaults
    # are resolved at call time because this file loads before OT.conf does.
    class RemoveOrphanedApproximatedVhosts
      CHORE_NAME = :remove_orphaned_approximated_vhosts

      # Set to APPLY_VALUE to let the chore delete. Anything else is a dry run.
      APPLY_ENV   = 'APPROXIMATED_VHOST_CLEANUP'
      APPLY_VALUE = 'apply'

      # Seconds to wait after each Approximated API call. Same figure
      # VerifyDomain uses between calls in bulk mode.
      API_PAUSE = 0.5

      # Approximated's status for a vhost that serves traffic through another
      # proxy. DNS cannot see this case.
      PROXIED_STATUS = 'ACTIVE_SSL_PROXIED'
      UNKNOWN_STATUS = 'UNKNOWN'

      # ApproximatedClient raises this text for a 404 (VerifyDomain matches on
      # the same string in #vhost_not_found?).
      NOT_FOUND_TEXT = 'Could not find Virtual Host'

      # Fields removed once the remote vhost is gone.
      CLEARED_FIELDS = [:vhost, :vhost_fetch_failed_at].freeze

      # Raised when the Approximated API fails in a way that is not "vhost not
      # found". Local state is left alone so the next run retries.
      class CleanupFailed < StandardError; end

      # Address lookup over the system resolvers. An empty answer is "no
      # evidence": Resolv reports NXDOMAIN, SERVFAIL, REFUSED and a timeout
      # the same way, so the caller must not read it as "points nowhere".
      class DnsLookup
        Snapshot = Data.define(:addresses, :cnames)

        TIMEOUTS = [2, 3].freeze # seconds per attempt

        # @param hostname [String]
        # @return [Snapshot] addresses as strings, cnames lowercased without
        #   the trailing dot; both empty when the lookup failed
        def lookup(hostname)
          # The trailing dot keeps resolv.conf's search list out of the lookup.
          fqdn = "#{hostname.to_s.strip.chomp('.')}."

          Resolv::DNS.open do |dns|
            dns.timeouts = TIMEOUTS
            addresses    = dns.getaddresses(fqdn)
            cnames       = dns.getresources(fqdn, Resolv::DNS::Resource::IN::CNAME)

            Snapshot.new(
              addresses: addresses.map(&:to_s),
              cnames: cnames.map { |rr| rr.name.to_s.downcase.chomp('.') },
            )
          end
        rescue StandardError => ex
          OT.ld "[DnsLookup] #{hostname}: #{ex.class}: #{ex.message}"
          Snapshot.new(addresses: [], cnames: [])
        end
      end

      # @param client [Module, nil] Approximated HTTP client (default: ApproximatedClient)
      # @param resolver [#lookup, nil] returns a DnsLookup::Snapshot (default: DnsLookup)
      # @param features [Module, nil] config accessor (default: DomainValidation::Features)
      # @param config [Hash, nil] application config (default: OT.conf)
      # @param apply [Boolean, nil] only `true` deletes, nil reads APPLY_ENV, anything
      #   else (false, or a non-boolean such as 'true') is a dry run
      # @param pause [Numeric] seconds to wait after each API call
      # @param sleeper [#call] receives the pause (default: Kernel#sleep)
      def initialize(client: nil, resolver: nil, features: nil, config: nil,
                     apply: nil, pause: API_PAUSE, sleeper: nil)
        @client   = client
        @resolver = resolver
        @features = features
        @config   = config
        @apply    = apply
        @pause    = pause
        @sleeper  = sleeper
      end

      # @param domain [Onetime::CustomDomain]
      # @return [true, nil] true when the record's vhost state was cleared
      # @raise [CleanupFailed] the Approximated API failed; state untouched
      def call(domain)
        return unless vhost_state?(domain)

        name = domain.display_domain.to_s.strip.downcase
        return skip(domain, 'record has no display_domain') if name.empty?
        return skip(domain, 'system strategy is approximated or not set') unless strategy_permits_cleanup?
        return skip(domain, 'no Approximated API key configured') unless api_key_configured?
        return skip(domain, 'unparseable vhost data; needs manual review', level: :warn) unless vhost_parseable?(domain)
        return skip(domain, 'stored vhost belongs to another hostname', level: :warn) unless vhost_matches_domain?(domain)

        evidence = dns_evidence(name)
        return skip(domain, "DNS evidence is #{evidence}") unless evidence == :moved

        unless apply?
          logger.info 'Dry run: DNS has moved off Approximated; vhost is a deletion candidate',
            chore: CHORE_NAME,
            domain: name,
            domain_extid: domain.extid,
            apply_with: "#{APPLY_ENV}=#{APPLY_VALUE}"
          return
        end

        remove_vhost(domain, name)
      end

      # 1a. The strategy must be known and must not be approximated. A blank
      # value is treated as unknown rather than as the passthrough default.
      #
      # @return [Boolean]
      def strategy_permits_cleanup?
        name = strategy_name.to_s.strip.downcase
        return false if name.empty? || name == 'approximated'

        !features.approximated?
      end

      # 1b. @return [Boolean]
      def api_key_configured?
        !features.api_key.to_s.strip.empty?
      end

      # `source` value CaddyOnDemandStrategy::VHOST_SOURCE puts on the status
      # blob it writes from its own probe. Approximated's payload has no
      # `source` key.
      PROBE_SOURCE                 = 'tls_probe'
      APPROXIMATED_CLEANUP_PENDING = 'approximated_vhost_pending_cleanup'

      # 1c. Apart from that probe blob, `vhost` is only ever written from an
      # Approximated API response, so any other content is Approximated-era
      # state. Unparseable content still counts as state so that it is
      # reported (see #vhost_parseable?) instead of silently ignored.
      #
      # @param domain [Onetime::CustomDomain]
      # @return [Boolean]
      def vhost_state?(domain)
        raw = domain.vhost
        return false if probe_blob?(domain, raw)
        return !raw.empty? if raw.is_a?(Hash)

        !['', '{}', 'null'].include?(raw.to_s.strip)
      end

      # The substring test avoids parsing every Approximated blob twice.
      #
      # @return [Boolean]
      def probe_blob?(domain, raw)
        if raw.is_a?(Hash)
          return raw['source'] == PROBE_SOURCE && raw[APPROXIMATED_CLEANUP_PENDING] != true
        end
        return false unless raw.to_s.include?(PROBE_SOURCE)

        stored = stored_vhost(domain)
        !stored.nil? &&
          stored['source'] == PROBE_SOURCE &&
          stored[APPROXIMATED_CLEANUP_PENDING] != true
      end

      # Content that is not a JSON object (garbage, a JSON array or scalar)
      # cannot tell us which hostname the vhost was created for, so the rename
      # guard below has nothing to check. Skip and leave it for an operator.
      #
      # @param domain [Onetime::CustomDomain]
      # @return [Boolean] true when the stored content is a Hash
      def vhost_parseable?(domain)
        !stored_vhost(domain).nil?
      end

      # A renamed domain keeps the vhost JSON of its old hostname. Deleting by
      # the new name would miss it and deleting by the old name could hit a
      # vhost that now serves a different record.
      #
      # @param domain [Onetime::CustomDomain]
      # @return [Boolean] true when the stored address is absent or matches;
      #   false when the stored content cannot be read
      def vhost_matches_domain?(domain)
        stored = stored_vhost(domain)
        return false if stored.nil?

        incoming = stored['incoming_address'].to_s.strip.downcase
        incoming.empty? || incoming == domain.display_domain.to_s.strip.downcase
      end

      # 1d, first half: where does the domain resolve from here?
      #
      # proxy_ip may list several entries separated by commas or whitespace.
      # Each is a single address or a CIDR range (203.0.113.0/24); a range
      # covers every address inside it. Entries that do not parse are ignored.
      #
      # @param name [String] display domain
      # @return [Symbol] :moved, :on_approximated, :indeterminate
      def dns_evidence(name)
        lookup_name = Onetime::DomainValidation::AsciiHostname.call(name)
        proxy_host  = features.proxy_host.to_s.strip.downcase.chomp('.')
        cluster     = parse_networks(features.proxy_ip.to_s.split(/[\s,]+/))

        unless proxy_host.empty?
          host_addresses = parse_networks(resolver.lookup(proxy_host).addresses)
          # A cluster hostname we cannot resolve leaves the comparison blind.
          return :indeterminate if host_addresses.empty?

          cluster |= host_addresses
        end

        classify_dns(resolver.lookup(lookup_name), cluster, proxy_host)
      rescue Onetime::DomainValidation::AsciiHostname::ConversionError => ex
        OT.ld "[#{self.class.name.split('::').last}] Cannot resolve #{name.inspect}: #{ex.message}"
        :indeterminate
      end

      # Pure comparison of a lookup against the cluster's addresses.
      #
      # @param snapshot [DnsLookup::Snapshot]
      # @param cluster [Array<String, IPAddr>] Approximated addresses and CIDR ranges
      # @param proxy_host [String] Approximated CNAME target, may be empty
      # @return [Symbol] :moved, :on_approximated, :indeterminate
      def classify_dns(snapshot, cluster, proxy_host)
        networks = parse_networks(cluster)
        return :indeterminate if networks.empty?

        addresses = parse_networks(snapshot.addresses)
        return :indeterminate if addresses.empty?
        return :on_approximated if addresses.any? { |address| in_cluster?(networks, address) }
        return :on_approximated if !proxy_host.empty? && snapshot.cnames.include?(proxy_host)

        :moved
      end

      # 1d, second half: does Approximated itself still see traffic?
      #
      # @param data [Hash, nil] 'data' from get_vhost_by_incoming_address
      # @return [Symbol] :idle, :serving, :indeterminate
      def classify_live_vhost(data)
        return :indeterminate unless data.is_a?(Hash)

        status = data['status'].to_s
        return :indeterminate if status.empty? || status == UNKNOWN_STATUS
        return :serving if status == PROXIED_STATUS
        return :serving if data['is_resolving'] == true || data['apx_hit'] == true
        return :indeterminate unless data['is_resolving'] == false

        :idle
      end

      private

      def remove_vhost(domain, name)
        live = fetch_live_vhost(name)

        unless live == :gone
          verdict = classify_live_vhost(live)
          unless verdict == :idle
            logger.info 'Skipping: DNS has moved but Approximated does not report the vhost idle',
              chore: CHORE_NAME,
              domain: name,
              domain_extid: domain.extid,
              verdict: verdict,
              status: live.is_a?(Hash) ? live['status'] : nil
            return
          end

          delete_remote(name)
        end

        clear_local_state(domain)

        logger.info 'Removed orphaned Approximated vhost',
          chore: CHORE_NAME,
          domain: name,
          domain_extid: domain.extid,
          remote: live == :gone ? 'already gone' : 'deleted'

        true
      end

      # @return [Hash, nil, Symbol] the vhost 'data', or :gone for a 404
      def fetch_live_vhost(name)
        res = paced { client.get_vhost_by_incoming_address(features.api_key, name) }
        return :gone if res.code == 404
        raise CleanupFailed, "vhost status check for #{name} returned #{res.code}" unless res.code == 200

        payload = res.parsed_response
        payload.is_a?(Hash) ? payload['data'] : nil
      rescue HTTParty::ResponseError => ex
        return :gone if not_found?(ex)

        raise CleanupFailed, "vhost status check for #{name} failed: #{ex.message}"
      end

      def delete_remote(name)
        res = paced { client.delete_vhost(features.api_key, name) }
        return if res.success? || res.code == 404

        raise CleanupFailed, "vhost delete for #{name} returned #{res.code}"
      rescue HTTParty::ResponseError => ex
        return if not_found?(ex)

        raise CleanupFailed, "vhost delete for #{name} failed: #{ex.message}"
      end

      # save_fields writes only the named fields (nil ones are HDEL'd), so a
      # record loaded at the start of a long batch cannot overwrite a
      # `verified` change VerifyDomain made in the meantime.
      def clear_local_state(domain)
        CLEARED_FIELDS.each { |field| domain.send(:"#{field}=", nil) }
        domain.updated = OT.now.to_i
        domain.save_fields(*CLEARED_FIELDS, :updated)
      end

      # Parsed here rather than through CustomDomain#parse_vhost, which maps
      # bad JSON to {} (indistinguishable from "no incoming_address") and
      # writes an error line on every call.
      #
      # @return [Hash, nil] nil when the content is not a JSON object
      def stored_vhost(domain)
        raw = domain.vhost
        return raw if raw.is_a?(Hash)

        parsed = JSON.parse(raw.to_s)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError, TypeError
        nil
      end

      def not_found?(error)
        error.message.to_s.include?(NOT_FOUND_TEXT)
      end

      # The housekeeping loop has no pacing of its own, so wait after every
      # API call, including a failed one.
      def paced
        yield
      ensure
        sleeper.call(@pause) if @pause.to_f.positive?
      end

      # IPAddr compares by value, so case and zero compression in an IPv6
      # literal do not matter, and "a.b.c.d/nn" becomes a range.
      #
      # @return [Array<IPAddr>] entries that do not parse are dropped
      def parse_networks(list)
        Array(list).filter_map do |entry|
          next entry if entry.is_a?(IPAddr)

          IPAddr.new(entry.to_s.strip)
        rescue IPAddr::Error
          nil
        end.uniq
      end

      # Same address family only: an IPv4 range says nothing about an IPv6
      # address, and IPAddr#include? across families is not reliable.
      def in_cluster?(networks, address)
        networks.any? { |network| network.family == address.family && network.include?(address) }
      end

      def skip(domain, reason, level: :debug)
        logger.public_send(
          level,
          "Skipping: #{reason}",
          chore: CHORE_NAME,
          domain: domain.display_domain,
          domain_extid: domain.extid,
        )
        nil
      end

      # Only the literal `true` applies. Any other non-nil value ('false',
      # 'true', 1) is a dry run rather than a truthy accident.
      def apply?
        return @apply == true unless @apply.nil?

        ENV.fetch(APPLY_ENV, nil) == APPLY_VALUE
      end

      # Same key Strategy.for_config reads, without its passthrough default.
      def strategy_name
        (@config || OT.conf || {}).dig('features', 'domains', 'validation_strategy')
      end

      def client
        @client || Onetime::DomainValidation::ApproximatedClient
      end

      def features
        @features || Onetime::DomainValidation::Features
      end

      def resolver
        @resolver ||= DnsLookup.new
      end

      def sleeper
        @sleeper || Kernel.method(:sleep)
      end

      def logger
        Onetime.get_logger('Chores')
      end
    end
  end
end

Onetime::CustomDomain.chore :remove_orphaned_approximated_vhosts,
  Onetime::Chores::RemoveOrphanedApproximatedVhosts.new
