# lib/onetime/paseto/access_token.rb
#
# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'time'

require_relative 'v4_public'
require_relative 'keyring'

module Onetime
  module Paseto
    # The API bearer token: a PASETO v4.public token whose payload is the set
    # of registered claims below, and whose footer names the signing key.
    #
    #   payload  {"sub":"ur...","aud":"onetimesecret:api:v3","iss":"<site.host>",
    #             "iat":"...","nbf":"...","exp":"...","jti":"...","scope":["*"]}
    #   footer   {"kid":"<16 hex>"}
    #
    # Claims (PASETO registered claims, RFC 3339 UTC timestamps):
    #
    #   sub    the customer's external identifier (never the objid)
    #   aud    the API surface the token is for; a token minted for the v3
    #          API is refused anywhere that expects another audience
    #   iss    the issuing deployment (site.host)
    #   iat    issued at; a token from the future is refused
    #   nbf    not before (same instant as iat)
    #   exp    expiry; required, never defaulted
    #   jti    128 random bits, for logs and a future denylist
    #   scope  ["*"]: the codebase has no narrower grants yet, so anything
    #          else is refused rather than silently widened
    #
    # Verification order follows the PASETO guidance: parse, pick the key by
    # the footer's `kid`, verify the signature, and only then read the
    # claims. Nothing in the payload is trusted before the signature check.
    module AccessToken
      SCOPE_ALL   = '*'
      DEFAULT_TTL = 3600
      MIN_TTL     = 60
      MAX_TTL     = 86_400

      # Tolerance for `iat`/`nbf` slightly in the future (clock drift between
      # nodes). `exp` gets no leeway: an expired token is expired.
      CLOCK_SKEW = 60

      MAX_SUBJECT_BYTES = 128

      # The verified contents of a token. Times are UTC Time objects.
      Claims = Data.define(:subject, :audience, :issuer, :issued_at, :not_before, :expires_at, :jti, :scope, :kid) do
        def expires_in(now = Time.now)
          [(expires_at - now).ceil, 0].max
        end
      end

      class << self
        # Clamp a configured lifetime into [MIN_TTL, MAX_TTL]. A value that
        # is not a positive integer falls back to DEFAULT_TTL.
        #
        # @param value [Integer, String, nil]
        # @return [Integer] seconds
        def clamp_ttl(value)
          ttl = Integer(value.to_s, 10)
          ttl.clamp(MIN_TTL, MAX_TTL)
        rescue ArgumentError, TypeError
          DEFAULT_TTL
        end

        # Mint a token.
        #
        # @param subject [String] the customer extid
        # @param keyring [Keyring]
        # @param audience [String]
        # @param issuer [String]
        # @param ttl [Integer] seconds; clamped into [MIN_TTL, MAX_TTL]
        # @param now [Time]
        # @return [Array(String, Claims)] the token and what it says
        def issue(subject:, keyring:, audience:, issuer:, ttl: DEFAULT_TTL, now: Time.now)
          raise ArgumentError, 'subject must not be empty' if subject.to_s.empty?

          issued_at  = Time.at(now.to_i).utc
          expires_at = issued_at + clamp_ttl(ttl)
          key        = keyring.signing_key
          claims     = Claims.new(
            subject: subject.to_s,
            audience: audience.to_s,
            issuer: issuer.to_s,
            issued_at: issued_at,
            not_before: issued_at,
            expires_at: expires_at,
            jti: SecureRandom.urlsafe_base64(16),
            scope: [SCOPE_ALL],
            kid: key.kid,
          )

          payload = JSON.generate(
            'sub' => claims.subject,
            'aud' => claims.audience,
            'iss' => claims.issuer,
            'iat' => rfc3339(claims.issued_at),
            'nbf' => rfc3339(claims.not_before),
            'exp' => rfc3339(claims.expires_at),
            'jti' => claims.jti,
            'scope' => claims.scope,
          )
          footer  = JSON.generate('kid' => key.kid)

          [V4Public.sign(key.private_key, payload, footer: footer), claims]
        end

        # Verify a token and return its claims.
        #
        # @param token [String]
        # @param keyring [Keyring]
        # @param audience [String] the audience this verifier serves
        # @param issuer [String] the issuer this verifier accepts
        # @param now [Time]
        # @return [Claims]
        # @raise [MalformedToken] not a v4.public token, or not decodable
        # @raise [UnknownKey] the footer names no key this deployment holds
        # @raise [InvalidSignature]
        # @raise [TokenExpired] `exp` has passed
        # @raise [InvalidClaims] any other claim problem (missing, malformed,
        #   wrong audience or issuer, not yet valid, unsupported scope)
        def verify(token, keyring:, audience:, issuer:, now: Time.now)
          parsed = V4Public.parse(token)
          kid    = V4Public.footer_kid(parsed.footer)
          raise UnknownKey, 'footer names no usable kid' if kid.nil?

          key = keyring.verification_key(kid)
          raise UnknownKey, "unknown kid #{kid}" if key.nil?

          payload, = V4Public.verify(key.public_key, parsed)
          claims   = parse_claims(payload, kid)
          validate!(claims, audience: audience, issuer: issuer, now: now)
          claims
        end

        private

        def rfc3339(time)
          time.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        end

        def parse_claims(payload, kid)
          data = JSON.parse(payload, max_nesting: 4)
          raise InvalidClaims, 'payload is not a JSON object' unless data.is_a?(Hash)

          Claims.new(
            subject: string_claim(data, 'sub', max_bytes: MAX_SUBJECT_BYTES),
            audience: string_claim(data, 'aud'),
            issuer: string_claim(data, 'iss'),
            issued_at: time_claim(data, 'iat'),
            not_before: time_claim(data, 'nbf', required: false),
            expires_at: time_claim(data, 'exp'),
            jti: string_claim(data, 'jti', required: false),
            scope: scope_claim(data),
            kid: kid,
          )
        rescue JSON::ParserError
          raise InvalidClaims, 'payload is not valid JSON'
        end

        def validate!(claims, audience:, issuer:, now:)
          now = now.utc
          raise TokenExpired, 'token expired' unless claims.expires_at > now
          raise InvalidClaims, 'token not yet valid' if claims.not_before && claims.not_before > now + CLOCK_SKEW
          raise InvalidClaims, 'token issued in the future' if claims.issued_at > now + CLOCK_SKEW
          raise InvalidClaims, 'audience mismatch' unless claims.audience == audience.to_s
          raise InvalidClaims, 'issuer mismatch' unless claims.issuer == issuer.to_s
          raise InvalidClaims, 'unsupported scope' unless claims.scope == [SCOPE_ALL]

          true
        end

        def string_claim(data, name, required: true, max_bytes: 1024)
          value = data[name]
          if value.nil?
            raise InvalidClaims, "missing #{name}" if required

            return nil
          end
          raise InvalidClaims, "#{name} is not a string" unless value.is_a?(String)
          raise InvalidClaims, "#{name} is empty" if value.empty?
          raise InvalidClaims, "#{name} too long" if value.bytesize > max_bytes

          value
        end

        # PASETO timestamps are RFC 3339 strings. Anything else -- including
        # a numeric epoch -- is malformed.
        def time_claim(data, name, required: true)
          value = data[name]
          if value.nil?
            raise InvalidClaims, "missing #{name}" if required

            return nil
          end
          raise InvalidClaims, "#{name} is not a string" unless value.is_a?(String)

          Time.iso8601(value).utc
        rescue ArgumentError
          raise InvalidClaims, "#{name} is not an RFC 3339 timestamp"
        end

        def scope_claim(data)
          scope = data['scope']
          raise InvalidClaims, 'missing scope' if scope.nil?
          raise InvalidClaims, 'scope is not an array of strings' unless scope.is_a?(Array) && scope.all?(String)

          scope
        end
      end
    end
  end
end
