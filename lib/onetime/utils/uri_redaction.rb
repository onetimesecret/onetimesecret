# frozen_string_literal: true

# Dependency-free and outside the Onetime namespace: standalone auth migrations
# use this before the application exists, including guards on defined?(Onetime).
module OnetimeUriRedaction
  def self.redact(value, keep_username: false, require_scheme: false, mask: '***')
    text   = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    scheme = text[%r{\A[a-z][a-z0-9+.-]*://}i]
    return mask if require_scheme && scheme.nil?

    prefix = scheme || text[%r{\A//}] || ''
    rest   = text.delete_prefix(prefix)
    at     = rest.rindex('@')
    query  = rest.index('?')
    # A question mark before the last @ is ambiguous: either part of the
    # password or a query containing @. Retaining either suffix could leak.
    return "#{prefix}#{mask}" if at && query && query < at

    if at
      userinfo    = rest[0...at]
      replacement = if keep_username
                      username, separator, = userinfo.partition(':')
                      separator.empty? ? username : "#{username}:#{mask}"
                    else
                      mask
                    end
      rest        = "#{replacement}@#{rest[(at + 1)..]}"
    end

    "#{prefix}#{rest.sub(/\?.*\z/m, "?#{mask}")}"
  end
end
