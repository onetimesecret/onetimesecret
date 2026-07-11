# lib/onetime/operations/email/error_scrub.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    module Email
      # Redact provider credentials from an exception message before it crosses
      # the wire into the colonel deliverability UI.
      #
      # The provider status / lookup / messages ops surface a degraded `error`
      # string when a live provider call fails, so an operator can see WHY a
      # provider is unavailable (a timeout, an auth failure). AWS and Lettermint
      # SDK errors do not normally embed the outbound Authorization credential in
      # their message — but a gem that echoed the failing request could, and the
      # site-wide invariant is that no secret (team token, AWS key) ever reaches
      # a response payload. This scrubs the known credential shapes we send while
      # leaving the diagnostic text intact.
      module ErrorScrub
        extend self

        # Provider credential shapes we hand to the SDKs. Order-independent;
        # each match is replaced with a fixed redaction marker.
        PATTERNS = [
          /lm_team_[A-Za-z0-9_-]+/,        # Lettermint team token
          /lm_[A-Za-z0-9_-]{8,}/,          # Lettermint project token
          /AKIA[0-9A-Z]{16}/,              # AWS access key id
          %r{[A-Za-z0-9/+=]{40}},          # AWS secret access key (40-char b64)
        ].freeze

        REDACTED = '[redacted]'

        # @param ex [Exception, String, nil]
        # @return [String] "ClassName: scrubbed message" — safe for the wire.
        def scrub(ex)
          message = ex.respond_to?(:message) ? ex.message.to_s : ex.to_s
          prefix  = ex.is_a?(Exception) ? "#{ex.class}: " : ''
          "#{prefix}#{redact(message)}"
        end

        def redact(text)
          PATTERNS.reduce(text.to_s) { |acc, pat| acc.gsub(pat, REDACTED) }
        end
      end
    end
  end
end
