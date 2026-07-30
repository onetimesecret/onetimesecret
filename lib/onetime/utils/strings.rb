# lib/onetime/utils/strings.rb
#
# frozen_string_literal: true

require 'mail'
require 'public_suffix'

module Onetime
  module Utils
    module Strings
      unless defined?(VALID_CHARS)
        # Symbols used in character sets for random string generation.
        # Includes common special characters that are generally safe for use
        # in generated identifiers and passwords.
        SYMBOLS         = %w[* $ ! ? ( ) @ # % ^].freeze
        AMBIGUOUS_CHARS = %w[i l o 1 I O 0].freeze

        # Complete character set for random string generation.
        # Includes lowercase letters (a-z), uppercase letters (A-Z),
        # digits (0-9), and symbols for maximum effect in generated strings.
        VALID_CHARS = [
          ('a'..'z').to_a,
          ('A'..'Z').to_a,
          ('0'..'9').to_a,
          *SYMBOLS,
        ].flatten.freeze

        # Unambiguous character set that excludes visually similar characters.
        # Removes potentially confusing characters (i, l, o, 1, I, O, 0) to
        # improve readability and reduce user errors when manually entering
        # generated strings.
        VALID_CHARS_SAFE = VALID_CHARS.reject { |char| AMBIGUOUS_CHARS.include?(char) }.freeze
        TRUTHY_VALUES    = %w[1 true yes on y t].freeze
      end

      # Generates a random string of specified length using predefined
      # character sets. Offers both unambiguous and standard character sets for
      # different use cases.
      #
      # @param len [Integer] Length of the generated string (default: 12)
      # @param unambiguous [Boolean] Whether to use the unambiguous character set
      #   (default: true)
      # @return [String] A randomly generated string of the specified length
      #
      # @example Generate a unambiguous 12-character string
      #   Utils.strand         # => "kF8mN2qR9xPw"
      #   Utils.strand(8)      # => "kF8mN2qR"
      #
      # @example Generate using full character set
      #   Utils.strand(8, false) # => "il0O1o$!"
      #
      # @see VALID_CHARS for details on the complete character set
      # @see VALID_CHARS_SAFE for details on the unambiguous character set
      # @security Cryptographically secure - uses SecureRandom.random_number which
      #   provides cryptographically secure random number generation. Suitable for
      #   generating secure tokens, passwords, and other security-critical identifiers.
      def strand(len = 12, unambiguous = true)
        raise ArgumentError, 'Length must be positive' unless len.positive?

        chars        = unambiguous ? VALID_CHARS_SAFE : VALID_CHARS
        charset_size = chars.length

        Array.new(len) { chars[SecureRandom.random_number(charset_size)] }.join
      end

      # Configuration constants for email masking
      EMAIL_MASK_MIN_LOCAL = 2    # chars to keep at start of local part
      EMAIL_MASK_CHAR      = '*'  # masking character
      EMAIL_MASK_LENGTH    = 3    # number of mask characters

      # U+FFFD REPLACEMENT CHARACTER. Shared so the producers that mark invalid
      # bytes with it (Diagnose#utf8_safe_deep, `customers diagnose --full`) and
      # the consumer that has to strip it before matching (#obscure_email) can
      # never drift onto different markers — a marker #obscure_email does not
      # know about is a marker that defeats EMAIL_PATTERN, which prints the
      # address in the clear.
      UNICODE_REPLACEMENT_CHAR = "\u{FFFD}"

      # RFC 5321/5322-compliant email pattern for matching
      # Supports: local-part@domain where local-part allows dots, plus, etc.
      # This pattern is intentionally permissive to catch edge cases while
      # Mail::Address handles validation during parsing.
      # Uses atomic group (?>) on local part to prevent ReDoS attacks.
      #
      # Letter/number classes are Unicode (\p{L}\p{N}), not [A-Z0-9]: Truemail
      # accepts a unicode local part, so `josé@example.com` is storable, and an
      # ASCII-only class would leave it printed in the clear by every caller of
      # #obscure_email. The domain side is widened for the same reason (IDNs).
      # \b is encoding-aware in Onigmo, so it still anchors correctly around
      # non-ASCII letters.
      EMAIL_PATTERN = /
        \b
        (?>[\p{L}\p{N}._%+'-]+)  # local part: atomic group prevents backtracking
        @
        [\p{L}\p{N}.-]+          # domain: alphanumeric, dots, hyphens
        \.
        \p{L}{2,}                # TLD: at least 2 letters
        \b
      /ix

      # Obscures email addresses by replacing most characters with asterisks
      # while preserving a minimal prefix for partial readability. Uses the
      # mail gem's Address parser for robust email handling.
      #
      # @param text [String] Text containing email addresses to obscure
      # @return [String] Text with email addresses masked
      #
      # @example Basic usage
      #   obscure_email("Contact tom@myspace.com please")
      #   # => "Contact to***@m***.com please"
      #
      # @example Short local part
      #   obscure_email("a@example.org")
      #   # => "a@e***.org"
      #
      # @example Subdomain handling
      #   obscure_email("user@mail.example.co.uk")
      #   # => "us***@m***.co.uk"
      #
      # Normalize an email address for consistent storage and comparison.
      #
      # NFC matters because e-acute can be encoded two ways:
      #   NFC (composed):   U+00E9        -> single codepoint
      #   NFD (decomposed): U+0065 U+0301 -> e + combining accent
      # Without normalization, identical-looking emails hash differently.
      #
      # @param email [String] Raw email address
      # @return [String] Normalized email (NFC, case-folded, stripped)
      #
      # @see Onetime::Utils::EmailHash.normalize_email (private, parallel copy
      #   kept to avoid load-order dependency — EmailHash loads early in boot
      #   before the full Utils module is available)
      def normalize_email(email)
        email.to_s.strip.unicode_normalize(:nfc).downcase(:fold)
      end

      # Removes every byte run that is not valid UTF-8 so text of unknown
      # provenance — a datastore field, a request parameter — can be matched,
      # printed and JSON-encoded without raising.
      #
      # The replacement is a PRESENTATION choice, not a safety one — read that
      # carefully, because it USED to be a safety one and the comments here said
      # so. U+FFFD is not in EMAIL_PATTERN's character class, so a marker landing
      # inside an address (`us\u{FFFD}er@example.com`) stopped the match and
      # printed the address in full; dropping was the fail-closed default for
      # that reason. #obscure_email now strips markers as part of its own
      # normalization, so no caller's redaction depends on this default any
      # more, and marking is safe to hand to a redactor.
      #
      # Choose by what the reader needs to see:
      #   '' (default) — the text will be read as prose and the corruption is
      #     noise.
      #   UNICODE_REPLACEMENT_CHAR — the corruption IS the evidence. This is
      #     what the diagnose op's Result uses: colonel renders those sections
      #     verbatim, and a `locale: "en\xFF"` that reads back as a clean "en"
      #     is a diagnostic tool lying about the state it exists to report.
      #
      # A binary-tagged string is `valid_encoding?` whatever bytes it holds, and
      # matching one against a UTF-8 pattern raises Encoding::CompatibilityError,
      # so re-tag before consulting the flag.
      #
      # @param text [String] Text of unknown encoding
      # @param replacement [String] Stand-in for each invalid byte run
      # @return [String] Valid UTF-8 text
      def utf8_safe(text, replacement: '')
        text = text.dup.force_encoding(Encoding::UTF_8) unless text.encoding == Encoding::UTF_8
        text.valid_encoding? ? text : text.scrub(replacement)
      end

      # @note Uses Mail::Address for parsing, avoiding hand-rolled parsing
      #   edge cases while keeping the code short and auditable.
      def obscure_email(text)
        return text if text.nil? || text.empty?

        # This is a redaction helper on logging and CLI-output paths, and its
        # input is whatever the datastore or the request held — gsub raises
        # ArgumentError on invalid UTF-8, which would turn unreadable data into
        # an outage (see LoginRateLimiter, which obscures a request-supplied
        # address). Scrub first, then mask what remains.
        #
        # Two separate ways a marker can defeat the mask, so both are handled
        # here rather than assumed away upstream:
        #
        #   1. invalid bytes we scrub ourselves — dropped, not marked, so
        #      `us\xFFer@example.com` collapses to `user@example.com` and still
        #      matches EMAIL_PATTERN;
        #   2. a U+FFFD the INPUT already carries — someone upstream scrubbed in
        #      marker mode (Diagnose#utf8_safe_deep does exactly that, and its
        #      Result is this method's input on the CLI path). Deleting it is
        #      the same collapse, one layer later.
        #
        # Either way the character is not in EMAIL_PATTERN's class, and an
        # unmatched address is an address printed in full. This normalization is
        # the reason #utf8_safe's replacement is now a free choice for callers.
        #
        # The cost is deliberate: the masked path silently loses the corruption
        # marker (`verified\u{FFFD}` prints as `verified`). Operators who need
        # to see the corruption use `--full` or the colonel panel, both of which
        # keep the marker and skip this method entirely. A redactor's job is to
        # never leak; showing damage is someone else's.
        utf8_safe(text).delete(UNICODE_REPLACEMENT_CHAR).gsub(EMAIL_PATTERN) do |raw|
          mask_email_address(raw)
        end
      end

      # Checks if a value represents a truthy boolean value
      # @param value [Object] Value to check
      # @return [Boolean] true if value one of the TRUTHY_VALUES (case-insensitive)
      def yes?(value)
        !value.to_s.empty? && TRUTHY_VALUES.include?(value.to_s.downcase)
      end

      private

      # Masks a single email address string
      # @param raw [String] Raw email address to mask
      # @return [String] Masked email address
      def mask_email_address(raw)
        addr = ::Mail::Address.new(raw)
        return mask_unparsed_address(raw) unless addr.local && addr.domain

        local  = mask_string_head(addr.local, EMAIL_MASK_MIN_LOCAL)
        domain = mask_domain(addr.domain)
        "#{local}@#{domain}"
      rescue StandardError
        # Mail gem can raise various exceptions (ParseError, ArgumentError,
        # Encoding::CompatibilityError).
        mask_unparsed_address(raw)
      end

      # Last-resort mask for an address the mail gem could not parse. Returning
      # `raw` here would print in the clear the very address EMAIL_PATTERN just
      # identified, so mask without parsing: keep the local-part head and the
      # final label, which is all an operator needs to tell two addresses apart.
      # @param raw [String] Address that failed to parse
      # @return [String] Masked address
      def mask_unparsed_address(raw)
        local, _, domain = raw.include?('@') ? raw.rpartition('@') : [raw, '', '']
        mask             = EMAIL_MASK_CHAR * EMAIL_MASK_LENGTH
        tld              = domain.split('.').last
        masked_domain    = tld.to_s.empty? ? mask : "#{mask}.#{tld}"
        "#{mask_string_head(local, EMAIL_MASK_MIN_LOCAL)}@#{masked_domain}"
      end

      # Splits domain and masks the host portion, preserving TLD
      # Uses PublicSuffix for reliable TLD detection (handles .co.uk, .com.au, etc.)
      # @param domain [String] Full domain (e.g., "mail.example.co.uk")
      # @return [String] Masked domain (e.g., "m***.co.uk")
      def mask_domain(domain)
        parsed = PublicSuffix.parse(domain, ignore_private: true)

        # Build host from subdomain (trd) and second-level domain (sld)
        host = parsed.trd ? "#{parsed.trd}.#{parsed.sld}" : parsed.sld
        tld  = parsed.tld

        return tld if host.nil? || host.empty?

        masked_host = mask_string_head(host, 1)
        "#{masked_host}.#{tld}"
      rescue PublicSuffix::DomainNotAllowed, PublicSuffix::DomainInvalid
        # Fallback for invalid/unlisted domains: mask first part, keep rest
        parts = domain.split('.')
        return domain if parts.size < 2

        "#{mask_string_head(parts.first, 1)}.#{parts[1..].join('.')}"
      end

      # Masks a string keeping only the first N characters visible
      # @param str [String] String to mask
      # @param keep_head [Integer] Number of leading characters to preserve
      # @return [String] Masked string
      def mask_string_head(str, keep_head)
        return str if str.nil? || str.length <= keep_head

        visible = str[0, keep_head]
        "#{visible}#{EMAIL_MASK_CHAR * EMAIL_MASK_LENGTH}"
      end
    end
  end
end
