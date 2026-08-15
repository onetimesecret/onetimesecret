# spec/unit/onetime/middleware/registry_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/middleware/registry'
require 'onetime/middleware/security'

RSpec.describe Onetime::Middleware::Registry do
  # The nine components Security mounts today, in mount order.
  SECURITY_NINE = %w[
    UTF8Sanitizer
    AuthenticityToken
    HttpOrigin
    XSSHeader
    FrameOptions
    PathTraversal
    CookieTossing
    IPSpoofing
    StrictTransport
  ].freeze

  # Registered for later per-app profile steps; not consumed yet.
  NEW_THREE = %w[Deflater ContentSecurityPolicy SessionHijacking].freeze

  describe '.components' do
    it 'contains exactly the 12 known entries, Security nine first in order' do
      expect(described_class.components.keys).to eq(SECURITY_NINE + NEW_THREE)
    end

    it 'is frozen' do
      expect(described_class.components).to be_frozen
    end

    it 'gives every entry a key, a klass, and a warn_when_disabled flag' do
      described_class.components.each do |name, cfg|
        expect(cfg[:key]).to be_a(Symbol), "#{name} missing :key"
        expect(cfg[:klass]).to be_a(Class), "#{name} missing :klass"
        expect([true, false]).to include(cfg[:warn_when_disabled]),
          "#{name} missing :warn_when_disabled"
      end
    end

    it 'maps the expected classes and config keys for the new entries' do
      expect(described_class.fetch('Deflater'))
        .to include(key: :deflater, klass: Rack::Deflater)
      expect(described_class.fetch('ContentSecurityPolicy'))
        .to include(key: :content_security_policy,
                    klass: Rack::Protection::ContentSecurityPolicy)
      expect(described_class.fetch('SessionHijacking'))
        .to include(key: :session_hijacking,
                    klass: Rack::Protection::SessionHijacking)
    end
  end

  describe '.fetch' do
    it 'returns the entry for a registered name' do
      expect(described_class.fetch('FrameOptions')[:klass])
        .to eq(Rack::Protection::FrameOptions)
    end

    it 'raises KeyError for an unknown name' do
      expect { described_class.fetch('Nope') }.to raise_error(KeyError)
    end
  end

  describe 'HttpOrigin entry' do
    it 'uses the shared allow_if from HttpOriginOptions' do
      options = described_class.fetch('HttpOrigin')[:options]
      expect(options[:allow_if])
        .to equal(Onetime::Middleware::HttpOriginOptions::ALLOW_IF)
    end
  end

  describe '.warn_when_disabled?' do
    WARN_WHEN_DISABLED = %i[
      frame_options path_traversal strict_transport authenticity_token
      utf8_sanitizer http_origin xss_header cookie_tossing ip_spoofing
    ].freeze

    WARN_WHEN_DISABLED.each do |key|
      it "is true for #{key}" do
        expect(described_class.warn_when_disabled?(key)).to be(true)
      end
    end

    %i[deflater content_security_policy session_hijacking].each do |key|
      it "is false for #{key}" do
        expect(described_class.warn_when_disabled?(key)).to be(false)
      end
    end

    it 'accepts string keys' do
      expect(described_class.warn_when_disabled?('frame_options')).to be(true)
    end

    it 'is false for unknown keys' do
      expect(described_class.warn_when_disabled?(:nonexistent)).to be(false)
    end
  end

  describe 'Onetime::Middleware::Security integration' do
    it 'middleware_components equals the registry filtered to the Security nine, in order' do
      expected = SECURITY_NINE.to_h { |name| [name, described_class.fetch(name)] }
      expect(Onetime::Middleware::Security.middleware_components).to eq(expected)
    end

    it 'exposes entries identical to (not copies of) the registry entries' do
      SECURITY_NINE.each do |name|
        expect(Onetime::Middleware::Security.middleware_components[name])
          .to equal(described_class.fetch(name))
      end
    end

    it 'derives WARN_WHEN_DISABLED_KEYS from the registry flags' do
      expect(Onetime::Middleware::Security::WARN_WHEN_DISABLED_KEYS)
        .to match_array(%w[
          frame_options path_traversal strict_transport authenticity_token
          utf8_sanitizer http_origin xss_header cookie_tossing ip_spoofing
        ])
    end

    it 'keeps the AuthenticityToken allow_if reachable via the historical access path' do
      allow_if = Onetime::Middleware::Security
        .middleware_components['AuthenticityToken'][:options][:allow_if]
      expect(allow_if).to respond_to(:call)
    end
  end
end
