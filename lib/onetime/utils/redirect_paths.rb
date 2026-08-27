# lib/onetime/utils/redirect_paths.rb
#
# frozen_string_literal: true

module Onetime
  module Utils
    # Server-side validation for post-authentication return destinations
    # (issue #4305).
    #
    # A `redirect` value arrives as an attacker-controllable query parameter,
    # is persisted server-side across the signup -> verification-email ->
    # sign-in journey, and is eventually handed back to the SPA as a
    # navigation target. Every one of those is a trust boundary, so the value
    # is re-validated at each hop rather than trusted because it was validated
    # once at capture time.
    #
    # This is the Ruby half of a two-sided contract: `src/utils/redirect.ts`
    # (isValidInternalPath) applies the SAME ruleset in the browser before
    # navigating. Keep the two in lockstep — a rule relaxed on one side only
    # produces a value the other side silently drops (best case) or an open
    # redirect (worst case).
    #
    # That lockstep is ENFORCED, not merely requested here:
    # `tests/fixtures/redirect_path_cases.json` is a single accept/reject table
    # read by BOTH spec/unit/onetime/utils/redirect_paths_spec.rb and
    # src/tests/utils/redirect.spec.ts. Change a rule below and the fixture
    # goes with it — otherwise one of those two suites turns red.
    #
    # ACCEPTS: absolute-path references only, query string and fragment
    # included and preserved verbatim (`/secret/abc?view=raw#content`).
    #
    # REJECTS (non-exhaustive, see the checks below for the authoritative
    # list): absolute URLs (`https://attacker.example`), protocol-relative
    # references (`//evil.example`), the backslash variant browsers normalize
    # to a protocol-relative reference (`/\evil.example`), percent-encoded
    # traversal (`/%2e%2e/admin`), percent-encoded protocol-relative
    # (`/%2fevil.example`), raw control characters (header/log injection), and
    # anything longer than MAX_PATH_LENGTH.
    module RedirectPaths
      unless defined?(MAX_PATH_LENGTH)
        # Mirrors the 2048 cap in src/utils/redirect.ts. Long enough for any
        # real internal path with query + fragment, short enough that a
        # persisted redirect cannot be used as a storage primitive.
        MAX_PATH_LENGTH = 2048

        # C0 controls plus DEL. Rejected in BOTH the raw and the decoded form:
        # raw because they have no business in a URL, decoded because
        # `%0d%0a` is the classic response-splitting / log-injection payload.
        CONTROL_CHARS = /[\x00-\x1F\x7F]/

        # A `%` that is not the start of a valid two-hex-digit escape. Its
        # presence means the value is not a well-formed percent-encoded
        # string, so decoding "fails" and the value is rejected rather than
        # guessed at.
        MALFORMED_ESCAPE = /%(?![0-9A-Fa-f]{2})/

        PERCENT_ESCAPE = /%([0-9A-Fa-f]{2})/
      end

      # True when `value` is a safe internal navigation target.
      #
      # @param value [Object] candidate path, typically straight off the wire
      # @return [Boolean]
      def safe_internal_path?(value)
        return false unless value.is_a?(String)
        return false unless value.valid_encoding?

        # Length before anything else: never run regexes over an unbounded
        # attacker-supplied string.
        return false if value.empty? || value.length > MAX_PATH_LENGTH

        # Absolute-path reference, and ONLY that. `//host` and `/\host` are
        # both read as protocol-relative references by browsers.
        return false unless value.start_with?('/')

        return false if ['/', '\\'].include?(value[1])

        # No backslash anywhere: browsers normalize `\` to `/` in URLs, so any
        # occurrence is either an escape attempt or a Windows-path artifact.
        return false if value.include?('\\')
        return false if value.include?('://')
        return false if value.match?(CONTROL_CHARS)

        decoded = percent_decode_once(value)
        return false if decoded.nil?

        # Re-apply the structural checks to the decoded form so a single layer
        # of percent-encoding cannot smuggle any of them past.
        return false if decoded.include?('\\')
        return false if decoded.match?(CONTROL_CHARS)
        return false if decoded.start_with?('//')
        return false if traversal_segment?(decoded)

        true
      end

      # Convenience wrapper for the capture/surface hooks: returns the value
      # when it validates, nil otherwise, so callers can write
      # `path = OT::Utils.internal_path_or_nil(param)`.
      #
      # @param value [Object]
      # @return [String, nil]
      def internal_path_or_nil(value)
        safe_internal_path?(value) ? value : nil
      end

      private

      # Percent-decode exactly ONE layer. Single-layer is deliberate: the
      # value is handed to a browser that will itself decode once, so
      # validating the once-decoded form is validating what the browser will
      # act on. Returns nil when the input is not well-formed percent-encoding
      # or decodes to invalid UTF-8 (both are "decoding failed" -> reject).
      def percent_decode_once(value)
        return nil if value.match?(MALFORMED_ESCAPE)

        # Decode on a BINARY copy: a multi-byte character split across several
        # escapes decodes to individual bytes, and substituting those into a
        # UTF-8 string raises Encoding::CompatibilityError.
        bytes   = value.b.gsub(PERCENT_ESCAPE) { Regexp.last_match(1).hex.chr }
        decoded = bytes.dup.force_encoding(Encoding::UTF_8)

        decoded.valid_encoding? ? decoded : nil
      end

      # A literal `..` PATH SEGMENT, not a bare `..` substring: `/a/../b` and
      # `/..` are traversal, `/files/a..b` is a legitimate filename.
      def traversal_segment?(decoded)
        decoded.split('/', -1).any?('..')
      end
    end
  end
end
