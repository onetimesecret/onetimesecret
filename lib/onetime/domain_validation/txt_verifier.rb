# lib/onetime/domain_validation/txt_verifier.rb
#
# frozen_string_literal: true

require_relative 'txt_resolver'

module Onetime
  module DomainValidation
    # TxtVerifier - Checks a TXT ownership challenge with our own DNS lookup.
    #
    # Returns the three-outcome contract of BaseStrategy#validate_ownership:
    #
    #   exactly one TXT value, equal to the challenge   -> validated: true
    #   NXDOMAIN, NOERROR without TXT data, or TXT
    #   values that are not "exactly one, matching"     -> validated: false
    #   SERVFAIL, REFUSED, timeout, network error, a
    #   hostname with no A-label form, or any exception -> validated: nil,
    #                                                      indeterminate: true
    #
    # The split between false and nil is the point of this class. A failed
    # lookup says nothing about the customer's DNS, so it must not demote a
    # verified domain (callers leave stored state alone on nil). NXDOMAIN and
    # an empty NOERROR answer are the resolver stating that the record is not
    # there, so they must demote — otherwise a deleted TXT record would hold
    # `verified` forever.
    #
    # "Exactly one" mirrors Approximated's check-records-match-exactly, so
    # both strategies accept and reject the same zones.
    #
    # An internationalised hostname is looked up in its A-label form
    # (AsciiHostname). Queried as typed it would come back NXDOMAIN, which is
    # our encoding speaking and not the customer's DNS; a name that cannot be
    # converted is therefore indeterminate and no lookup is made.
    #
    # Every lookup result carries source: 'native' and a :data Array shaped
    # like Approximated's 'records' payload (string keys; 'actual_values' is
    # the Array of values seen, or false when the lookup produced no answer;
    # 'address' is the hostname as stored, not its A-label form).
    #
    # Usage:
    #   TxtVerifier.new.verify(domain.validation_record, domain.txt_validation_value)
    #
    class TxtVerifier
      SOURCE = 'native'

      # @param resolver_factory [#call] Returns an object responding to
      #   #lookup(hostname) -> TxtResolver::Answer and #close. A new resolver
      #   is built for each #verify and always closed. Specs inject a fake
      #   here; nothing in this class touches the network itself.
      def initialize(resolver_factory: -> { TxtResolver.new })
        @resolver_factory = resolver_factory
      end

      # @param hostname [String] Where the challenge lives (validation_record)
      # @param expected [String] The challenge value (txt_validation_value)
      # @return [Hash] See BaseStrategy#validate_ownership
      def verify(hostname, expected)
        hostname = hostname.to_s
        hostname = hostname.strip if hostname.valid_encoding? # else left for AsciiHostname to refuse
        expected = expected.to_s.strip

        # Without a challenge there is nothing to prove. This is the one result
        # without :data, and what that means is the caller's decision:
        # CaddyOnDemandStrategy adds :mode, so VerifyDomain stores the false;
        # ApproximatedStrategy#classify_native reads a false without :data as
        # non-definitive and does not demote on it.
        if hostname.empty? || expected.empty?
          return { validated: false, message: 'TXT challenge is not configured for this domain', source: SOURCE }
        end

        query_name = ascii_hostname(hostname)
        if query_name.nil?
          return indeterminate(hostname, expected, 'no A-label form', message: 'Hostname cannot be queried as typed (indeterminate)')
        end

        resolver = @resolver_factory.call
        classify(hostname, expected, resolver.lookup(query_name))
      rescue StandardError => ex
        OT.lw "[TxtVerifier] TXT lookup failed for #{hostname}: #{ex.class}: #{ex.message}"
        indeterminate(hostname, expected, "#{ex.class}: #{ex.message}")
      ensure
        close(resolver)
      end

      private

      def classify(hostname, expected, answer)
        unless answer.definitive?
          OT.lw "[TxtVerifier] Indeterminate TXT lookup for #{hostname}: #{answer.rcode_name}"
          return indeterminate(hostname, expected, answer.rcode_name)
        end

        values  = answer.values
        matched = values == [expected]
        message = if matched
          'TXT record validated'
        elsif values.empty?
          'TXT record not found'
        else
          "TXT record mismatch (#{values.size} value(s) found, exactly one matching value required)"
        end

        {
          validated: matched,
          message: message,
          source: SOURCE,
          data: [record(hostname, expected, match: matched, actual_values: values, rcode: answer.rcode_name)],
        }
      end

      # @return [String, nil] nil when the name cannot go on the wire
      def ascii_hostname(hostname)
        AsciiHostname.call(hostname)
      rescue AsciiHostname::ConversionError => ex
        OT.lw "[TxtVerifier] Not looking up #{hostname.inspect}: #{ex.message}"
        nil
      end

      def indeterminate(hostname, expected, reason, message: "DNS lookup returned no result (indeterminate: #{reason})")
        {
          validated: nil,
          indeterminate: true,
          message: message,
          source: SOURCE,
          data: [record(hostname, expected, match: false, actual_values: false, error: reason)],
        }
      end

      def record(hostname, expected, match:, actual_values:, **extra)
        {
          'type' => 'TXT',
          'address' => hostname,
          'match_against' => expected,
          'match' => match,
          'actual_values' => actual_values,
        }.merge(extra.transform_keys(&:to_s))
      end

      # A close failure must not replace the result of the lookup.
      def close(resolver)
        resolver&.close
      rescue StandardError => ex
        OT.lw "[TxtVerifier] Failed to close resolver: #{ex.class}: #{ex.message}"
      end
    end
  end
end
