# spec/unit/onetime/initializers/setup_paseto_keys_spec.rb
#
# frozen_string_literal: true

# SetupPasetoKeys (#2427): the keyring in Runtime.security is a function of
# site.secret and SECRET_PREVIOUS, and nothing else.
#
# Run: pnpm run test:rspec spec/unit/onetime/initializers/setup_paseto_keys_spec.rb

require 'spec_helper'
require 'onetime/initializers/setup_paseto_keys'

RSpec.describe Onetime::Initializers::SetupPasetoKeys do
  subject(:initializer) { described_class.new }

  let(:secret) { 'decafbad' * 8 }

  before do
    @previous_env = ENV.fetch('SECRET_PREVIOUS', nil)
    ENV.delete('SECRET_PREVIOUS')
    allow(OT).to receive(:conf).and_return({ 'site' => { 'secret' => secret } })
    Onetime::Runtime.update_security(paseto_keyring: nil)
  end

  after do
    if @previous_env.nil?
      ENV.delete('SECRET_PREVIOUS')
    else
      ENV['SECRET_PREVIOUS'] = @previous_env
    end
    Onetime::Runtime.update_security(paseto_keyring: nil)
  end

  it 'declares its place in the boot graph' do
    expect(described_class.instance_variable_get(:@depends_on)).to eq([:logging, :secrets])
    expect(described_class.instance_variable_get(:@provides)).to eq([:paseto_keys])
  end

  it 'derives the keyring from site.secret and leaves the global secret alone' do
    Onetime::Runtime.update_security(global_secret: secret)
    initializer.execute(nil)

    keyring = Onetime::Runtime.security.paseto_keyring
    expect(keyring).to be_a(Onetime::Paseto::Keyring)
    expect(keyring.signing_key.kid).to eq(Onetime::Paseto::Keyring.derive(secret).signing_key.kid)
    expect(Onetime::Runtime.security.global_secret).to eq(secret)
    expect(Onetime::Paseto.keyring).to be(keyring)
  end

  it 'accepts tokens signed under every SECRET_PREVIOUS entry' do
    ENV['SECRET_PREVIOUS'] = "#{'feedface' * 8},#{'cafef00d' * 8}"
    initializer.execute(nil)

    kids = Onetime::Runtime.security.paseto_keyring.kids
    expect(kids.size).to eq(3)
    expect(kids).to include(Onetime::Paseto::Keyring.derive('feedface' * 8).signing_key.kid)
  end

  it 'refuses to run without a secret, like ConfigureFamilia' do
    allow(OT).to receive(:conf).and_return({ 'site' => { 'secret' => '' } })
    expect { initializer.execute(nil) }.to raise_error(Onetime::Problem, /site.secret/)
  end

  it 'Onetime::Paseto.keyring names the missing initializer when nothing was derived' do
    expect { Onetime::Paseto.keyring }.to raise_error(Onetime::Paseto::KeyringUnavailable, /SetupPasetoKeys/)
  end
end
