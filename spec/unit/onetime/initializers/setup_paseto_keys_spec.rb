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

  it 'derives nothing without a secret and lets the boot continue, failing closed at request time' do
    # development.allow_nil_global_secret admits an empty site.secret
    # (Onetime::Config.after_load); an optional feature's initializer must
    # not turn that boot into a failure. The strategy answers every
    # presented token with a terminal refusal while the keyring is missing.
    Onetime::Runtime.update_security(paseto_keyring: Onetime::Paseto::Keyring.derive('stale' * 13))
    boot_logger = instance_double(SemanticLogger::Logger, warn: nil, debug: nil)
    allow(OT).to receive_messages(conf: { 'site' => { 'secret' => '' } }, boot_logger: boot_logger)

    expect { initializer.execute(nil) }.not_to raise_error
    expect(boot_logger).to have_received(:warn).with(/site.secret is empty/)
    expect(Onetime::Runtime.security.paseto_keyring).to be_nil
    expect { Onetime::Paseto.keyring }.to raise_error(Onetime::Paseto::KeyringUnavailable)
  end

  it 'treats a nil site.secret the same as an empty one' do
    allow(OT).to receive_messages(
      conf: { 'site' => {} },
      boot_logger: instance_double(SemanticLogger::Logger, warn: nil, debug: nil),
    )

    expect { initializer.execute(nil) }.not_to raise_error
    expect(Onetime::Runtime.security.paseto_keyring).to be_nil
  end

  it 'Onetime::Paseto.keyring names the missing initializer when nothing was derived' do
    expect { Onetime::Paseto.keyring }.to raise_error(Onetime::Paseto::KeyringUnavailable, /SetupPasetoKeys/)
  end
end
