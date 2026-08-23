# lib/onetime/utils/admin_host_allowlist.rb
#
# frozen_string_literal: true

require_relative '../../middleware/detect_host'
require_relative 'domain_parser'

module Onetime
  module Utils
    # Shared judgment for `site.admin.allowed_hosts` (#4062): which configured
    # entries can EVER match a request's detected host, and why the others
    # cannot.
    #
    # Two call sites must agree exactly, so the judgment lives in neither:
    #
    #   Onetime::Config.check_admin_allowed_hosts — WARNs at boot when an
    #     explicitly configured allowlist has nothing enforceable left in it.
    #     The LOUD path; it owns the operator-facing diagnostic text.
    #   Onetime::Middleware::AdminNetworkIsolation — enforces the surviving
    #     hosts, and DENIES both admin surfaces when it is constructed with an
    #     explicit allowlist that has nothing enforceable. The RUNTIME half of
    #     the same judgment: the boot check explains, this denies.
    #
    # If those two ever disagreed, the app would boot with a warning about a
    # config the middleware then serves happily, or deny a config the boot
    # check called fine. One classifier, one answer.
    #
    # ## What makes an entry unenforceable
    #
    # Matching is exact, ASCII-only, against the host Rack::DetectHost
    # validated. So an entry is rejected when it is a pattern (`*.example.com`
    # matches nothing — there is no glob matching here), when it is non-ASCII
    # (this project ships no IDN library; DomainParser.basically_valid? rejects
    # U-labels, so DetectHost can never emit one), when it does not parse as a
    # hostname at all, or when it is a host DetectHost would never emit —
    # `localhost`, `localhost.localdomain`, and every IP literal.
    #
    # Routability is judged with DetectHost's OWN predicate (public via its
    # `extend ClassMethods`) rather than a local copy, so the two cannot drift.
    module AdminHostAllowlist
      # Disables the host gate. Honored ANYWHERE in the list, not only as the
      # sole entry — see Classification#unenforceable? for why a sibling entry
      # does not make it ambiguous.
      WILDCARD = '*'

      # Why an entry was rejected, in the words shown to the operator. Used by
      # both boot WARNs — the config check's and the middleware's
      # rejected-entries line: one judgment, one vocabulary.
      REJECTION_REASONS = {
        wildcard_pattern: 'wildcard patterns are not supported — list each hostname explicitly',
        non_ascii: 'non-ASCII — supply the punycode (xn--) form',
        unparseable: 'not a hostname',
        not_routable: 'not a routable hostname — localhost forms and IP literals are never detected as a host',
      }.freeze

      # The outcome of classifying one configured list.
      #
      # @!attribute hosts
      #   @return [Array<String>] normalized entries that can match
      # @!attribute rejected
      #   @return [Array<Array(String, Symbol)>] [entry, reason] pairs
      # @!attribute wildcard
      #   @return [Boolean] whether a bare `*` was listed
      Classification = Data.define(:hosts, :rejected, :wildcard) do
        # Nothing was configured at all (as opposed to configured badly).
        def empty?
          hosts.empty? && rejected.empty? && !wildcard
        end

        # `*` and nothing else: the documented escape hatch, written cleanly.
        # Callers deciding whether the gate is OFF must ask #wildcard, not this
        # — see #unenforceable?. This narrower predicate exists only to decide
        # whether there are IGNORED SIBLINGS worth naming in a WARN.
        def wildcard_only?
          wildcard && hosts.empty? && rejected.empty?
        end

        # Configured, but no entry survives — the fail-loud case.
        #
        # AN EXPLICIT `*` ANYWHERE IN THE LIST MAKES THIS FALSE, whatever else
        # is listed. `*` is the documented request for "host gate off"; it is
        # not made ambiguous by a sibling entry, and the sibling is ignored
        # either way. Reading `wildcard_only?` here instead would classify
        # `ADMIN_ALLOWED_HOSTS="*,10.0.0.5"` as unenforceable — a total deny in
        # the middleware — while the diagnostic tells the operator to do
        # exactly what they had just done: set `*`.
        def unenforceable?
          !empty? && !wildcard && hosts.empty?
        end
      end

      class << self
        # Classify a raw allowlist. Side-effect free: no logging, no raising —
        # each caller decides what its posture does with the result.
        #
        # BLANK ENTRIES ARE SKIPPED, NOT REJECTED — a DELIBERATE asymmetry with
        # #4063's LINK_DOMAINS, where `LINK_DOMAINS="  "` is a boot error.
        # ADMIN_ALLOWED_HOSTS="   " classifies as empty?, which sends the gate
        # to the canonical-anchor fallback: the RESTRICTIVE default. There is
        # no over-exposure to deny over, so the RUNTIME treats it exactly like
        # unset. The BOOT check no longer stays quiet about it, though (#4127):
        # check_admin_allowed_hosts distinguishes a set-but-blank list (an
        # empty? classification of a non-nil raw) from unset (nil) and WARNs,
        # because on a localhost/bare-IP install the anchor fallback
        # self-disables and the operator's written config yields no host gate
        # at all. The unenforceable cases remain the loud ones — an entry that
        # survives stripping but can never match leaves the operator's intent
        # to restrict silently unfulfilled — and those warn at boot and deny
        # both surfaces at runtime.
        #
        # @param raw [Array<String>, String, nil]
        # @return [Classification]
        def classify(raw)
          wildcard = false
          hosts    = []
          rejected = []

          Array(raw).each do |value|
            entry = value.to_s.strip
            next if entry.empty?

            if entry == WILDCARD
              wildcard = true
              next
            end

            reason = rejection_reason(entry)
            if reason
              rejected << [entry, reason]
            else
              hosts << normalize_host(entry)
            end
          end

          Classification.new(hosts: hosts.uniq, rejected: rejected.uniq, wildcard: wildcard)
        end

        # Why this entry cannot match, or nil when it can.
        #
        # THE WILDCARD TEST READS THE NORMALIZED HOST, NOT THE RAW ENTRY. A
        # scheme, port, path and trailing slash are all accepted shapes here
        # (see #normalize_host), so scanning the raw string for `*` rejected
        # `https://admin.example.com/*` — an entry whose HOSTNAME is perfectly
        # enforceable — and told the operator "wildcard patterns are not
        # supported" about a hostname containing no wildcard. A pattern in the
        # host itself (`*.example.com`) survives normalization unchanged and is
        # still rejected here; a bare `*` never reaches this method at all,
        # having been taken as the escape hatch in #classify.
        #
        # @param entry [String] a stripped, non-empty configured entry
        # @return [Symbol, nil] a key of REJECTION_REASONS
        def rejection_reason(entry)
          return :non_ascii unless entry.ascii_only?

          host = normalize_host(entry)
          return :unparseable if host.nil?
          return :wildcard_pattern if host.include?(WILDCARD)
          return :not_routable unless Rack::DetectHost.valid_domain_name?(host)

          nil
        end

        # The single normalization applied to BOTH sides of the comparison:
        # downcase, strip a `:port` and any scheme (DomainParser), strip a
        # trailing root dot (ours — `example.com.` is a legal client-supplied
        # FQDN that DetectHost passes through untouched, and it must match a
        # configured `example.com`).
        #
        # @param value [String, URI, nil]
        # @return [String, nil]
        def normalize_host(value)
          host = DomainParser.extract_hostname(value)
          return nil if host.nil?

          host = host.sub(/\.+\z/, '')
          host.empty? ? nil : host
        end

        # Human-readable "entry: reason" lines for an operator-facing message.
        #
        # @param rejected [Array<Array(String, Symbol)>]
        # @return [Array<String>]
        def describe_rejections(rejected)
          rejected.map { |entry, reason| "#{entry.inspect}: #{REJECTION_REASONS.fetch(reason, reason)}" }
        end
      end
    end
  end
end
