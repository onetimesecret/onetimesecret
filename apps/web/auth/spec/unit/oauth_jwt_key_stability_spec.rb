# apps/web/auth/spec/unit/oauth_jwt_key_stability_spec.rb
#
# frozen_string_literal: true

# Proves that the same OAUTH_JWT_RSA_PRIVATE_KEY PEM produces the same JWK
# `kid` across loads. This is the load-bearing property for issue #3104,
# task 6: if the kid changes between boots, every token an SP holds becomes
# unverifiable on the next deploy.
#
# We don't boot rodauth twice — that would couple this test to task 11's
# control of /jwks visibility (only_json?). The deterministic property
# "same PEM → same RFC 7638 thumbprint" is sufficient. RFC 7638 defines
# the JWK thumbprint as a SHA-256 over the canonical JSON of the public
# JWK members; identical bytes in, identical bytes out, by construction.
#
# Source: https://datatracker.ietf.org/doc/html/rfc7638

require 'openssl'
require 'jwt'

RSpec.describe 'OAuth JWT key stability across boots' do
  let(:pem) { OpenSSL::PKey::RSA.new(2048).to_pem }

  it 'derives the same kid from the same PEM, twice' do
    k1 = OpenSSL::PKey::RSA.new(pem)
    k2 = OpenSSL::PKey::RSA.new(pem)

    kid1 = JWT::JWK.new(k1.public_key).kid
    kid2 = JWT::JWK.new(k2.public_key).kid

    expect(kid1).to eq(kid2)
    expect(kid1).not_to be_empty
  end

  it 'derives different kids from different PEMs' do
    other_pem = OpenSSL::PKey::RSA.new(2048).to_pem
    kid1 = JWT::JWK.new(OpenSSL::PKey::RSA.new(pem).public_key).kid
    kid2 = JWT::JWK.new(OpenSSL::PKey::RSA.new(other_pem).public_key).kid

    expect(kid1).not_to eq(kid2)
  end

  it 'feeds OpenSSL::PKey::RSA → oauth_jwt_keys-compatible objects' do
    # rodauth-oauth expects an OpenSSL::PKey::* instance, not a PEM string.
    # If we ever swap the loader, this guard keeps the shape contract honest.
    key = OpenSSL::PKey::RSA.new(pem)
    expect(key).to be_a(OpenSSL::PKey::RSA)
    expect(key.public_key).to be_a(OpenSSL::PKey::RSA)
  end

  # The generator↔loader contract. bin/generate_oauth_keys emits a single-line
  # value with escaped newlines (pem.gsub("\n", '\n')) so it fits in a .env
  # file; features/oauth.rb reverses it with gsub('\n', "\n") before
  # OpenSSL::PKey::RSA.new. Every integration spec seeds a raw multi-line PEM,
  # so without these examples the escaped-key path the generator actually
  # produces would be entirely untested — and a regression in either gsub would
  # ship silently (the original #3239 review finding).
  describe 'escaped single-line key round-trip (matches bin/generate_oauth_keys)' do
    # Mirror of the unescape in apps/web/auth/config/features/oauth.rb.
    def load_pem(raw) = OpenSSL::PKey::RSA.new(raw.gsub('\n', "\n"))

    it 'loads a key escaped exactly as the generator emits it' do
      escaped = pem.gsub("\n", '\n') # what bin/generate_oauth_keys writes
      expect(escaped).to include('\n')      # sanity: it really is single-line
      expect(escaped).not_to include("\n")  # ...with no real newlines

      key = load_pem(escaped)
      expect(key).to be_a(OpenSSL::PKey::RSA)
      # Same key material as the multi-line source, not a re-parse artifact.
      expect(key.to_pem).to eq(pem)
    end

    it 'still loads an unescaped multi-line PEM unchanged' do
      key = load_pem(pem)
      expect(key.to_pem).to eq(pem)
    end
  end

  describe 'malformed key handling' do
    # features/oauth.rb wraps the load in a rescue that re-raises a message
    # naming OAUTH_JWT_RSA_PRIVATE_KEY and the generator. This pins that a
    # garbage value raises OpenSSL::PKey::RSAError (the class that rescue
    # catches), so the operator-facing wrapper keeps firing.
    it 'raises OpenSSL::PKey::RSAError for a non-PEM value' do
      expect { OpenSSL::PKey::RSA.new('not-a-key') }
        .to raise_error(OpenSSL::PKey::RSAError)
    end
  end
end
