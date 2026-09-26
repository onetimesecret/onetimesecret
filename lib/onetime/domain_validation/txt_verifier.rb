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
    #   SERVFAIL, REFUSED, timeout, network error, or
    #   any exception                                   -> validated: nil,
    #                                                      indeterminate: true
    #
    # The split between false and nil is the point of this class. A failed
    # lookup says nothing about the customer's DNS, so callers leave stored
    # state alone on nil. NXDOMAIN and an empty NOERROR answer are definitive
    # negatives from this resolver. The caller decides whether that one answer
    # is sufficient to demote: Caddy has no second checker, while Approximated
    # requires corroboration before revoking an existing verification when its
    # independent checker is indeterminate.
    #
    # "Exactly one" mirrors Approximated's check-records-match-exactly, so
    # both strategies accept and reject the same zones.
    #
    # Every result carries source: 'native' and a :data Array shaped like
    # Approximated's 'records' payload (string keys; 'actual_values' is the
    # Array of values seen, or false when the lookup produced no answer).
    # VerifyDomain#persist_changes only acts on a result that has :data.
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
        hostname = hostname.to_s.strip
        expected = expected.to_s.strip

        # Without a challenge there is nothing to prove. No :data, so callers
        # report the failure without changing stored state.
        if hostname.empty? || expected.empty?
          return { validated: false, message: 'TXT challenge is not configured for this domain', source: SOURCE }
        end

        resolver = @resolver_factory.call
        classify(hostname, expected, resolver.lookup(hostname))
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

      def indeterminate(hostname, expected, reason)
        {
          validated: nil,
          indeterminate: true,
          message: "DNS lookup returned no result (indeterminate: #{reason})",
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
