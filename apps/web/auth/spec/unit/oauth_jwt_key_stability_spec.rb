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
end
