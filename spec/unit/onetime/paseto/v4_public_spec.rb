# spec/unit/onetime/paseto/v4_public_spec.rb
#
# frozen_string_literal: true

# The v4.public codec against the official PASETO test vectors
# (spec/fixtures/paseto/v4.json, https://github.com/paseto-standard/test-vectors),
# plus the malformed-token edges the vectors do not cover. Pure: no boot, no
# datastore. Ed25519 signatures are deterministic, so signing a vector's
# payload with its secret key must reproduce its token byte for byte.
#
# Run: pnpm run test:rspec spec/unit/onetime/paseto/v4_public_spec.rb

require 'spec_helper'
require 'json'
require 'onetime/paseto'

RSpec.describe Onetime::Paseto::V4Public do
  # The official vectors from paseto-standard/test-vectors (v4.json), with the
  # redundant `secret-key-pem` / `public-key-pem` members removed: the raw hex
  # keys are the canonical form and the only one used here, and the PEM copies
  # trip the detect-private-key pre-commit hook. Everything else is verbatim.
  let(:vectors) do
    JSON.parse(File.read(File.expand_path('../../../fixtures/paseto/v4.json', __dir__))).fetch('tests')
  end
  let(:public_vectors) { vectors.select { |v| v['name'].start_with?('4-S') } }

  def hex(str) = [str].pack('H*')

  def private_key_for(vector)
    # The vector's secret key is the 64-byte libsodium form: seed || public key.
    described_class.private_key_from_seed(hex(vector.fetch('secret-key'))[0, 32])
  end

  def public_key_for(vector)
    described_class.public_key_from_raw(hex(vector.fetch('public-key')))
  end

  it 'reads three signing vectors from the fixture (guards against a vacuous pass)' do
    expect(public_vectors.map { |v| v['name'] }).to eq(%w[4-S-1 4-S-2 4-S-3])
  end

  describe '.sign' do
    it 'reproduces every official v4.public token byte for byte' do
      public_vectors.each do |vector|
        token = described_class.sign(
          private_key_for(vector), vector['payload'],
          footer: vector['footer'], implicit: vector['implicit-assertion'],
        )
        expect(token).to eq(vector['token']), vector['name']
      end
    end

    it 'derives the vector public key from the seed (OpenSSL raw key round trip)' do
      vector = public_vectors.first
      expect(private_key_for(vector).raw_public_key.unpack1('H*')).to eq(vector['public-key'])
    end
  end

  describe '.verify' do
    it 'accepts every official token and returns its payload and footer' do
      public_vectors.each do |vector|
        payload, footer = described_class.verify(public_key_for(vector), vector['token'],
          implicit: vector['implicit-assertion'])
        expect(payload).to eq(vector['payload']), vector['name']
        expect(footer).to eq(vector['footer']), vector['name']
        expect(payload.encoding).to eq(Encoding::UTF_8)
      end
    end

    it 'rejects the token when the implicit assertion differs (4-S-3)' do
      vector = public_vectors.find { |v| v['name'] == '4-S-3' }
      expect {
        described_class.verify(public_key_for(vector), vector['token'], implicit: '')
      }.to raise_error(Onetime::Paseto::InvalidSignature)
    end

    it 'rejects a token under a different key' do
      vector = public_vectors.first
      other  = described_class.private_key_from_seed(SecureRandom.random_bytes(32))
      expect {
        described_class.verify(described_class.public_key_from_raw(other.raw_public_key), vector['token'])
      }.to raise_error(Onetime::Paseto::InvalidSignature)
    end

    it 'rejects a payload altered after signing' do
      vector = public_vectors.find { |v| v['name'] == '4-S-2' }
      body, footer = vector['token'].delete_prefix(described_class::HEADER).split('.', 2)
      signed       = described_class.decode(body)
      tampered     = signed.dup
      tampered.setbyte(0, tampered.getbyte(0) ^ 0x01)
      token = "#{described_class::HEADER}#{described_class.encode(tampered)}.#{footer}"

      expect { described_class.verify(public_key_for(vector), token) }
        .to raise_error(Onetime::Paseto::InvalidSignature)
    end

    it 'rejects a footer altered after signing (the footer is authenticated)' do
      vector = public_vectors.find { |v| v['name'] == '4-S-2' }
      body, = vector['token'].delete_prefix(described_class::HEADER).split('.', 2)
      token = "#{described_class::HEADER}#{body}.#{described_class.encode('{"kid":"other"}')}"

      expect { described_class.verify(public_key_for(vector), token) }
        .to raise_error(Onetime::Paseto::InvalidSignature)
    end

    it 'rejects the public-purpose failure vector 4-F-2 (signed by an unknown key)' do
      vector = vectors.find { |v| v['name'] == '4-F-2' }
      expect(vector['expect-fail']).to be true
      expect { described_class.verify(public_key_for(public_vectors.first), vector['token']) }
        .to raise_error(Onetime::Paseto::InvalidSignature)
    end

    it 'rejects every non-public failure vector at parse time (wrong version or purpose)' do
      vectors.select { |v| v['expect-fail'] && v['name'] != '4-F-2' }.each do |vector|
        expect { described_class.parse(vector['token']) }
          .to raise_error(Onetime::Paseto::MalformedToken, /unsupported header/), vector['name']
      end
    end
  end

  describe '.parse' do
    let(:vector) { public_vectors.find { |v| v['name'] == '4-S-2' } }

    it 'splits message, signature and footer without verifying' do
      parsed = described_class.parse(vector['token'])
      expect(parsed.message).to eq(vector['payload'].b)
      expect(parsed.signature.bytesize).to eq(64)
      expect(parsed.footer).to eq(vector['footer'].b)
    end

    it 'returns an empty footer for a footerless token' do
      expect(described_class.parse(public_vectors.first['token']).footer).to eq('')
    end

    {
      'a non-string' => nil,
      'a v3.public header' => 'v3.public.abc',
      'a v4.local header' => 'v4.local.abc',
      'a bare header' => 'v4.public.',
      'padding in the payload' => 'v4.public.YWJj=',
      'standard base64 characters' => 'v4.public.YW+j/A',
      'a payload shorter than a signature' => "v4.public.#{Base64.urlsafe_encode64('short', padding: false)}",
      'a fourth segment' => 'v4.public.YWJj.YWJj.YWJj',
    }.each do |label, token|
      it "rejects #{label}" do
        expect { described_class.parse(token) }.to raise_error(Onetime::Paseto::MalformedToken)
      end
    end

    it 'rejects a token above MAX_TOKEN_BYTES before decoding' do
      token = described_class::HEADER + ('A' * described_class::MAX_TOKEN_BYTES)
      expect { described_class.parse(token) }.to raise_error(Onetime::Paseto::MalformedToken, /too long/)
    end
  end

  describe '.footer_kid' do
    it 'reads a well-formed kid' do
      expect(described_class.footer_kid('{"kid":"zVhMiPBP9fRf2snEcT7gFTioeA9COcNy9DfgL1W60haN"}'.b))
        .to eq('zVhMiPBP9fRf2snEcT7gFTioeA9COcNy9DfgL1W60haN')
    end

    {
      'an empty footer' => '',
      'a non-JSON footer' => "arbitrary-string-that-isn't-json",
      'a JSON array' => '["kid"]',
      'a non-string kid' => '{"kid":12}',
      'a kid with reserved characters' => '{"kid":"a.b/c"}',
      'an oversized kid' => "{\"kid\":\"#{'a' * 129}\"}",
      'a footer above the size bound' => "{\"kid\":\"a\",\"pad\":\"#{'x' * 1100}\"}",
      'invalid UTF-8' => "\xff\xfe".b,
    }.each do |label, footer|
      it "answers nil for #{label}" do
        expect(described_class.footer_kid(footer.b)).to be_nil
      end
    end
  end

  describe '.pae' do
    # Worked examples from the PASETO specification (Common/PAE).
    it 'matches the specification examples' do
      expect(described_class.pae.unpack1('H*')).to eq('0000000000000000')
      expect(described_class.pae('').unpack1('H*')).to eq('01000000000000000000000000000000')
      expect(described_class.pae('test').unpack1('H*')).to eq('0100000000000000040000000000000074657374')
    end

    it 'is unambiguous: moving bytes between pieces changes the encoding' do
      expect(described_class.pae('ab', 'c')).not_to eq(described_class.pae('a', 'bc'))
    end
  end

  describe 'key helpers' do
    it 'refuse seeds and public keys of the wrong length' do
      expect { described_class.private_key_from_seed('short') }.to raise_error(ArgumentError)
      expect { described_class.public_key_from_raw('short') }.to raise_error(ArgumentError)
    end
  end
end
