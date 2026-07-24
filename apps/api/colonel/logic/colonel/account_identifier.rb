# apps/api/colonel/logic/colonel/account_identifier.rb
#
# frozen_string_literal: true

module ColonelAPI
  module Logic
    module Colonel
      # Sanitizer for identifiers that may be an EMAIL ADDRESS.
      #
      # ## Why this exists
      #
      # `Onetime::Security::InputSanitizers#sanitize_identifier` strips every
      # character outside `[a-zA-Z0-9_-]`, so `user@example.com` arrives at the
      # resolver as `userexamplecom`. Every colonel surface that documents an
      # "email or extid" identifier (verify/unverify, purge, user detail, the
      # three membership verbs) was therefore email-blind: the email arm of
      # `Customer.load_by_extid_or_email` could never match and the request 404'd
      # with "not found".
      #
      # `sanitize_account_identifier` keeps the same strict allowlist posture —
      # a character allowlist, no HTML parsing — but widens it by exactly the
      # characters an email address needs (`@ . + %`). It is NOT a validator:
      # callers still resolve the result through
      # `Customer.load_by_extid_or_email` (or the membership resolver), which is
      # what decides whether the identifier names anything.
      #
      # ## Threat model
      #
      # The allowlist excludes whitespace, quotes, angle brackets, backslashes,
      # colons, slashes and every Redis/glob metacharacter, so the output is
      # still safe to interpolate into a key lookup or a log line. Length is
      # bounded at {MAX_LENGTH} (RFC 5321's 254-octet path limit, rounded) so a
      # pathological identifier can't be used to inflate a log or an index probe.
      #
      # Use `sanitize_identifier` (unchanged) for identifiers that can only ever
      # be an extid/objid — org ids, domain extids, session ids.
      module AccountIdentifier
        # Any character NOT valid in an extid/objid OR an email local/domain part.
        # Mirrors IDENTIFIER_STRIP_PATTERN plus `@ . + %`.
        ACCOUNT_IDENTIFIER_STRIP_PATTERN = /[^a-zA-Z0-9_\-.@+%]/

        # RFC 5321 caps a forward-path at 254 octets; extids are far shorter.
        MAX_LENGTH = 255

        # @param value [String, nil] raw identifier (email, extid, or objid)
        # @return [String] sanitized identifier, never nil
        def sanitize_account_identifier(value)
          value.to_s.strip.gsub(ACCOUNT_IDENTIFIER_STRIP_PATTERN, '').slice(0, MAX_LENGTH).to_s
        end

        # Resolve a sanitized identifier to a Customer, trying extid, then
        # email, then the internal objid — the resolution order every colonel
        # user surface uses (the users list exposes only extid, so that arm has
        # to win, but operators paste emails).
        #
        # `normalize_email` is a safe pass-through for an extid (extids are
        # already lowercase ASCII); it only matters when the value is an email
        # typed with capitals.
        #
        # @param identifier [String]
        # @return [Onetime::Customer, nil]
        def resolve_account(identifier)
          normalized = OT::Utils.normalize_email(identifier)
          Onetime::Customer.load_by_extid_or_email(normalized) ||
            Onetime::Customer.load(identifier)
        end
      end
    end
  end
end
