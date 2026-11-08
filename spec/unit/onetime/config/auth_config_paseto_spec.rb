# spec/unit/onetime/config/auth_config_paseto_spec.rb
#
# frozen_string_literal: true

# AuthConfig#paseto_enabled? and #paseto_token_ttl (#2427): read from the
# top-level `paseto` section, independent of the auth mode, and safe on a
# config that predates the section.
#
# Strategy mirrors auth_config_spec.rb: write a minimal YAML config to a temp
# file, point ConfigResolver at it, and reset the singleton between examples.
#
# Run: pnpm run test:rspec spec/unit/onetime/config/auth_config_paseto_spec.rb

require 'spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe Onetime::AuthConfig do
  let(:temp_dir) { Dir.mktmpdir('auth_config_paseto_test') }
  let(:config_path) { File.join(temp_dir, 'auth.yaml') }

  def write_config(yaml)
    File.write(config_path, yaml)
  end

  def load_config
    allow(Onetime::Utils::ConfigResolver).to receive(:resolve).with('auth').and_return(config_path)
    allow(Onetime::Utils::ConfigResolver).to receive(:defaults_path).with('auth').and_return(nil)
    Singleton.__init__(described_class)
    described_class.instance
  end

  after do
    Singleton.__init__(described_class)
    FileUtils.rm_rf(temp_dir)
  end

  it 'is disabled with the default lifetime when the section is absent (a pre-#2427 config)' do
    write_config("---\nmode: simple\nsimple: {}\nfull: {}\n")
    config = load_config

    expect(config.paseto_enabled?).to be false
    expect(config.paseto_token_ttl).to eq(Onetime::Paseto::AccessToken::DEFAULT_TTL)
  end

  it 'reads the section in simple mode' do
    write_config("---\nmode: simple\nsimple: {}\nfull: {}\npaseto:\n  enabled: true\n  token_ttl: 900\n")
    config = load_config

    expect(config.mode).to eq('simple')
    expect(config.paseto_enabled?).to be true
    expect(config.paseto_token_ttl).to eq(900)
  end

  it 'reads the section in full mode' do
    write_config("---\nmode: full\nsimple: {}\nfull:\n  database_url: \"sqlite::memory:\"\npaseto:\n  enabled: true\n")
    expect(load_config.paseto_enabled?).to be true
  end

  it 'treats only boolean true as enabled' do
    write_config("---\nmode: simple\nsimple: {}\nfull: {}\npaseto:\n  enabled: 'true'\n")
    expect(load_config.paseto_enabled?).to be false
  end

  it 'clamps the lifetime and defaults a malformed one' do
    write_config("---\nmode: simple\nsimple: {}\nfull: {}\npaseto:\n  enabled: true\n  token_ttl: 999999\n")
    expect(load_config.paseto_token_ttl).to eq(Onetime::Paseto::AccessToken::MAX_TTL)

    write_config("---\nmode: simple\nsimple: {}\nfull: {}\npaseto:\n  enabled: true\n  token_ttl: soon\n")
    expect(load_config.paseto_token_ttl).to eq(Onetime::Paseto::AccessToken::DEFAULT_TTL)
  end

  it 'the shipped defaults render disabled unless PASETO_ENABLED=true' do
    defaults = Onetime::Utils::ConfigResolver.defaults_path('auth')
    skip 'no shipped auth defaults file' unless defaults && File.exist?(defaults)

    previous = ENV.fetch('PASETO_ENABLED', nil)
    begin
      ENV.delete('PASETO_ENABLED')
      rendered = YAML.safe_load(ERB.new(File.read(defaults)).result(binding))
      expect(rendered.dig('paseto', 'enabled')).to be false
      expect(rendered.dig('paseto', 'token_ttl')).to eq(3600)

      ENV['PASETO_ENABLED'] = 'true'
      rendered              = YAML.safe_load(ERB.new(File.read(defaults)).result(binding))
      expect(rendered.dig('paseto', 'enabled')).to be true
    ensure
      previous.nil? ? ENV.delete('PASETO_ENABLED') : ENV['PASETO_ENABLED'] = previous
    end
  end
end
