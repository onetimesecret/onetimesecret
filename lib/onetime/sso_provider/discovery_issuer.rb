# lib/onetime/sso_provider/discovery_issuer.rb
#
# frozen_string_literal: true

module Onetime
  module SsoProvider
    # Compares the issuer an operator configured against the `issuer` an OIDC
    # discovery document declares.
    #
    # OpenID Connect Discovery 1.0 §4.3 requires the discovered issuer to be
    # IDENTICAL to the issuer URL used to fetch the document, and the ID
    # token `iss` claim is compared to the same value. Issuer identifiers are
    # therefore compared as exact strings: no case folding, no trailing-slash
    # trimming, no URL normalization. `https://idp.example.com` and
    # `https://idp.example.com/` are different issuers (Auth0, for example,
    # publishes its issuer WITH the trailing slash).
    #
    # A missing, empty, or non-string discovered issuer is a failure, as is a
    # missing configured issuer — there is nothing to compare against.
    #
    # Usage:
    #   result = DiscoveryIssuer.check(configured: 'https://idp.example.com/',
    #                                  discovered: doc['issuer'])
    #   result.ok?      # => true / false
    #   result.reason   # => :match, :mismatch, :missing_discovered,
    #                   #    :invalid_discovered, :missing_configured
    #
    module DiscoveryIssuer
      REASONS = [:match, :mismatch, :missing_discovered, :invalid_discovered, :missing_configured].freeze

      # Immutable outcome of one comparison. `discovered` carries the raw
      # value from the document (it may be a non-String when the reason is
      # :invalid_discovered); use #discovered_string for display.
      Result = Data.define(:reason, :configured, :discovered) do
        def ok?
          reason == :match
        end

        def mismatch?
          !ok?
        end

        # The discovered issuer when it is a String, else nil. Safe to render
        # or log without leaking arbitrary document structure.
        def discovered_string
          discovered.is_a?(String) ? discovered : nil
        end
      end

      extend self

      # @param configured [String, nil] the issuer the operator configured
      # @param discovered [Object] the `issuer` value from the discovery doc
      # @return [Result]
      def check(configured:, discovered:)
        Result.new(
          reason: reason_for(configured, discovered),
          configured: configured,
          discovered: discovered,
        )
      end

      # Convenience for a parsed discovery document. A non-Hash document
      # yields :missing_discovered.
      #
      # @param configured [String, nil]
      # @param document [Hash, Object] parsed discovery JSON
      # @return [Result]
      def check_document(configured:, document:)
        discovered = document.is_a?(Hash) ? document['issuer'] : nil
        check(configured: configured, discovered: discovered)
      end

      private

      def reason_for(configured, discovered)
        return :missing_configured unless configured.is_a?(String) && !configured.empty?
        return :missing_discovered if discovered.nil? || discovered == ''
        return :invalid_discovered unless discovered.is_a?(String)
        return :match if discovered == configured

        :mismatch
      end
    end
  end
end
