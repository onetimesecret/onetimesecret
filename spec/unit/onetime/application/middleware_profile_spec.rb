# spec/unit/onetime/application/middleware_profile_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# MiddlewareProfile (#4170 refactor step 2)
#
# Covers: profile definitions, class-level declaration + inheritance on
# Onetime::Application::Base, config-gated resolution against the middleware
# Registry, and the unknown-profile failure mode.
RSpec.describe Onetime::Application::MiddlewareProfile do
  # Records `use` calls like the manifest spec's MiddlewareRecorder.
  class ProfileRecorder
    attr_reader :used

    def initialize
      @used = []
    end

    def use(klass, *args, **kwargs, &blk)
      @used << [klass, kwargs]
    end
  end

  describe 'profile definitions' do
    it 'defines exactly the known profiles' do
      expect(described_class::PROFILES.keys).to eq(%i[standard authenticated_web internal])
    end

    it ':standard resolves to no components' do
      expect(described_class.fetch(:standard)).to eq([])
    end

    it ':internal resolves to no components (semantic marker only)' do
      expect(described_class.fetch(:internal)).to eq([])
    end

    it ":authenticated_web lists the auth app's production stack, in order" do
      expect(described_class.fetch(:authenticated_web)).to eq(
        %w[Deflater ContentSecurityPolicy FrameOptions HttpOrigin IPSpoofing PathTraversal SessionHijacking],
      )
    end

    it 'every profile component exists in the middleware Registry' do
      described_class::PROFILES.each_value do |names|
        names.each do |name|
          expect { Onetime::Middleware::Registry.fetch(name) }.not_to raise_error
        end
      end
    end

    it 'raises ArgumentError for an unknown profile name' do
      expect { described_class.fetch(:bogus) }.to raise_error(ArgumentError, /Unknown middleware profile/)
    end
  end

  describe 'class-level declaration and inheritance' do
    # Anonymous subclasses: nil .name keeps them out of the manifest spec's
    # coverage scan; should_skip_loading? keeps them out of registry mounts.
    let(:parent) do
      Class.new(Onetime::Application::Base) do
        def self.should_skip_loading? = true
        middleware_profile :authenticated_web
      end
    end

    it 'defaults to :standard on Base' do
      expect(Onetime::Application::Base.middleware_profile).to eq(:standard)
    end

    it 'defaults to :standard on a subclass with no declaration' do
      klass = Class.new(Onetime::Application::Base) do
        def self.should_skip_loading? = true
      end
      expect(klass.middleware_profile).to eq(:standard)
    end

    it 'returns the declared profile' do
      expect(parent.middleware_profile).to eq(:authenticated_web)
    end

    it 'inherits the superclass profile when the subclass declares none' do
      child = Class.new(parent)
      expect(child.middleware_profile).to eq(:authenticated_web)
    end

    it 'lets a subclass override its superclass profile' do
      child = Class.new(parent) { middleware_profile :internal }
      expect(child.middleware_profile).to eq(:internal)
    end

    it 'raises at declaration time for an unknown profile name' do
      expect {
        Class.new(Onetime::Application::Base) do
          def self.should_skip_loading? = true
          middleware_profile :not_a_profile
        end
      }.to raise_error(ArgumentError, /Unknown middleware profile/)
    end
  end

  describe '.apply (config-gated resolution)' do
    let(:recorder) { ProfileRecorder.new }

    def stub_middleware_config(settings)
      allow(Onetime).to receive(:conf).and_return('site' => { 'middleware' => settings })
    end

    it 'mounts nothing for an empty profile without touching config' do
      described_class.apply(:standard, recorder)
      expect(recorder.used).to be_empty
    end

    it 'does not mount components whose config keys are absent (falsy default)' do
      stub_middleware_config({})
      described_class.apply(:authenticated_web, recorder)
      expect(recorder.used).to be_empty
    end

    it 'mounts only components whose config keys are true, with Registry klass/options' do
      stub_middleware_config('frame_options' => true, 'http_origin' => true)
      described_class.apply(:authenticated_web, recorder)

      expect(recorder.used.map(&:first)).to eq([
        Rack::Protection::FrameOptions,
        Rack::Protection::HttpOrigin,
      ])
      # Options come straight from the Registry entry (shared HttpOriginOptions).
      expect(recorder.used.last.last).to eq(Onetime::Middleware::HttpOriginOptions.options)
    end

    it 'skips components whose key is explicitly false' do
      stub_middleware_config('frame_options' => false, 'deflater' => true)
      described_class.apply(:authenticated_web, recorder)
      expect(recorder.used.map(&:first)).to eq([Rack::Deflater])
    end

    it 'warns when a security-critical component is disabled' do
      stub_middleware_config('frame_options' => false)
      allow(OT).to receive(:lw)
      described_class.apply(:authenticated_web, recorder)
      # (PathTraversal, the profile's other security-critical component, also
      # warns because its key is absent — the assertion targets frame_options.)
      expect(OT).to have_received(:lw).with(/FrameOptions DISABLED.*site\.middleware\.frame_options/)
    end

    it 'raises for an unknown profile name' do
      expect { described_class.apply(:bogus, recorder) }.to raise_error(ArgumentError)
    end
  end
end
