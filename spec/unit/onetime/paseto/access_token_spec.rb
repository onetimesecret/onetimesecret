# spec/unit/onetime/paseto/access_token_spec.rb
#
# frozen_string_literal: true

# Claims: what POST /api/v3/token puts in a bearer token and what the
# strategy insists on before trusting one (#2427). Pure: no boot, no
# datastore; the clock is injected.
#
# Run: pnpm run test:rspec spec/unit/onetime/paseto/access_token_spec.rb

require 'spec_helper'
require 'json'
require 'onetime/paseto'

RSpec.describe Onetime::Paseto::AccessToken do
  let(:keyring)  { Onetime::Paseto::Keyring.derive('decafbad' * 8, 'cafef00d' * 8) }
  let(:now)      { Time.utc(2026, 10, 27, 12, 0, 0) }
  let(:audience) { Onetime::Paseto::V3_AUDIENCE }
  let(:issuer)   { 'us.onetimesecret.test' }
  let(:subject_extid) { 'ur0123456789abcdefghijklmno' }

  def issue(**overrides)
    described_class.issue(
      subject: subject_extid, keyring: keyring, audience: audience, issuer: issuer, ttl: 3600, now: now, **overrides,
    )
  end

  def verify(token, **overrides)
    described_class.verify(token, keyring: keyring, audience: audience, issuer: issuer, now: now + 1, **overrides)
  end

  # The payload and footer exactly as written, read through the codec with
  # the signing key (no claim validation).
  def decode(token)
    payload, footer = Onetime::Paseto::V4Public.verify(keyring.signing_key.public_key, token)
    [JSON.parse(payload), JSON.parse(footer)]
  end

  describe '.issue' do
    it 'signs the registered claims as RFC 3339 UTC strings with the kid in the footer' do
      token, claims = issue
      payload, footer = decode(token)

      expect(token).to start_with('v4.public.')
      expect(payload).to eq(
        'sub' => subject_extid,
        'aud' => audience,
        'iss' => issuer,
        'iat' => '2026-10-27T12:00:00Z',
        'nbf' => '2026-10-27T12:00:00Z',
        'exp' => '2026-10-27T13:00:00Z',
        'jti' => claims.jti,
        'scope' => ['*'],
      )
      expect(footer).to eq('kid' => keyring.signing_key.kid)
      expect(claims.kid).to eq(keyring.signing_key.kid)
      expect(claims.expires_at).to eq(now + 3600)
      expect(claims.expires_in(now)).to eq(3600)
    end

    it 'gives every token a fresh 128-bit jti' do
      jtis = Array.new(5) { issue.last.jti }
      expect(jtis.uniq.size).to eq(5)
      jtis.each { |jti| expect(Base64.urlsafe_decode64(jti).bytesize).to eq(16) }
    end

    it 'clamps the lifetime into the accepted range' do
      expect(issue(ttl: 1).last.expires_at).to eq(now + described_class::MIN_TTL)
      expect(issue(ttl: 10**9).last.expires_at).to eq(now + described_class::MAX_TTL)
      expect(issue(ttl: 'junk').last.expires_at).to eq(now + described_class::DEFAULT_TTL)
    end

    it 'refuses an empty subject' do
      expect { issue(subject: '') }.to raise_error(ArgumentError)
    end
  end

  describe '.clamp_ttl' do
    it 'reads integers and integer strings, clamps, and defaults anything else' do
      expect(described_class.clamp_ttl(900)).to eq(900)
      expect(described_class.clamp_ttl('900')).to eq(900)
      expect(described_class.clamp_ttl(0)).to eq(described_class::MIN_TTL)
      expect(described_class.clamp_ttl(10**6)).to eq(described_class::MAX_TTL)
      expect(described_class.clamp_ttl(nil)).to eq(described_class::DEFAULT_TTL)
      expect(described_class.clamp_ttl('1h')).to eq(described_class::DEFAULT_TTL)
      expect(described_class.clamp_ttl(1.5)).to eq(described_class::DEFAULT_TTL)
    end
  end

  describe '.verify' do
    it 'returns the claims of a token it issued' do
      token, issued = issue
      claims = verify(token)

      expect(claims).to eq(issued)
      expect(claims.subject).to eq(subject_extid)
      expect(claims.scope).to eq(['*'])
    end

    it 'accepts a token signed by a previous SECRET (rotation)' do
      previous_ring = Onetime::Paseto::Keyring.derive('cafef00d' * 8)
      token, = issue(keyring: previous_ring)

      claims = verify(token)
      expect(claims.kid).to eq(previous_ring.signing_key.kid)
      expect(claims.kid).not_to eq(keyring.signing_key.kid)
    end

    it 'refuses a token signed by a SECRET this deployment never held' do
      token, = issue(keyring: Onetime::Paseto::Keyring.derive('deadbeef' * 8))
      expect { verify(token) }.to raise_error(Onetime::Paseto::UnknownKey)
    end

    it 'refuses a token that reached its expiry, with its own error' do
      token, = issue
      expect { verify(token, now: now + 3600) }.to raise_error(Onetime::Paseto::TokenExpired)
      expect(Onetime::Paseto::TokenExpired.ancestors).to include(Onetime::Paseto::InvalidClaims)
      expect { verify(token, now: now + 3599) }.not_to raise_error
    end

    it 'refuses a token issued too far in the future, but tolerates clock skew' do
      token, = issue(now: now + described_class::CLOCK_SKEW + 1)
      expect { verify(token, now: now) }.to raise_error(Onetime::Paseto::InvalidClaims, /future|not yet valid/)

      skewed, = issue(now: now + described_class::CLOCK_SKEW - 1)
      expect { verify(skewed, now: now) }.not_to raise_error
    end

    it 'refuses another audience or issuer' do
      token, = issue
      expect { verify(token, audience: 'onetimesecret:api:account') }
        .to raise_error(Onetime::Paseto::InvalidClaims, /audience/)
      expect { verify(token, issuer: 'eu.onetimesecret.test') }
        .to raise_error(Onetime::Paseto::InvalidClaims, /issuer/)
    end

    it 'refuses what is not a v4.public token at all' do
      %w[v3.public.abc v4.local.abc Bearer not-a-token].each do |token|
        expect { verify(token) }.to raise_error(Onetime::Paseto::MalformedToken), token
      end
    end

    it 'refuses a token with no kid in its footer' do
      payload = JSON.generate('sub' => subject_extid, 'exp' => '2099-01-01T00:00:00Z')
      token   = Onetime::Paseto::V4Public.sign(keyring.signing_key.private_key, payload)
      expect { verify(token) }.to raise_error(Onetime::Paseto::UnknownKey)
    end

    # Tokens signed with the right key but hand-built claims: every claim
    # rule, each one proven by a token that differs in exactly that claim.
    describe 'claim rules' do
      let(:valid_claims) do
        {
          'sub' => subject_extid, 'aud' => audience, 'iss' => issuer,
          'iat' => '2026-10-27T12:00:00Z', 'nbf' => '2026-10-27T12:00:00Z', 'exp' => '2026-10-27T13:00:00Z',
          'jti' => 'abc', 'scope' => ['*'],
        }
      end

      def forged(claims)
        Onetime::Paseto::V4Public.sign(
          keyring.signing_key.private_key, JSON.generate(claims),
          footer: JSON.generate('kid' => keyring.signing_key.kid),
        )
      end

      it 'accepts the baseline (guards the forgery helper)' do
        expect(verify(forged(valid_claims)).subject).to eq(subject_extid)
      end

      it 'treats nbf and jti as optional, everything else as required' do
        expect { verify(forged(valid_claims.except('nbf', 'jti'))) }.not_to raise_error
        %w[sub aud iss iat exp scope].each do |claim|
          expect { verify(forged(valid_claims.except(claim))) }
            .to raise_error(Onetime::Paseto::InvalidClaims, /missing #{claim}/), claim
        end
      end

      {
        'a numeric exp' => { 'exp' => 4_102_444_800 },
        'a non-RFC3339 exp' => { 'exp' => 'tomorrow' },
        'a numeric sub' => { 'sub' => 42 },
        'an empty sub' => { 'sub' => '' },
        'an oversized sub' => { 'sub' => 'u' * 129 },
        'a narrower scope' => { 'scope' => ['secrets:read'] },
        'a widened scope' => { 'scope' => ['*', 'admin'] },
        'a string scope' => { 'scope' => '*' },
        'an nbf after exp' => { 'nbf' => '2026-10-27T14:00:00Z' },
      }.each do |label, change|
        it "refuses #{label}" do
          expect { verify(forged(valid_claims.merge(change))) }.to raise_error(Onetime::Paseto::InvalidClaims)
        end
      end

      it 'refuses a payload that is not a JSON object' do
        token = Onetime::Paseto::V4Public.sign(
          keyring.signing_key.private_key, '["sub"]', footer: JSON.generate('kid' => keyring.signing_key.kid),
        )
        expect { verify(token) }.to raise_error(Onetime::Paseto::InvalidClaims, /JSON object/)
      end

      it 'ignores claims it does not know (forward compatibility)' do
        expect { verify(forged(valid_claims.merge('org' => 'on123'))) }.not_to raise_error
      end
    end
  end
end
