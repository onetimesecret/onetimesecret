# spec/unit/onetime/application/registry_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Onetime::Application::Registry — mount-mapping filters
#
# create_mount_mappings previously skipped only @abstract classes while
# reregister_loaded_applications filtered on BOTH @abstract and
# should_skip_loading?. That asymmetry let a registered-but-should-skip class
# (e.g. one registered directly via the inherited hook rather than through a
# reset!) be mapped to a mount point. This spec pins the symmetric behavior.
RSpec.describe Onetime::Application::Registry do
  # Anonymous subclasses: nil .name keeps them out of the manifest spec's
  # coverage scan. `skip` is toggleable so these dummies opt OUT of loading
  # outside this spec (reset! in other specs re-discovers them via ObjectSpace).
  let!(:normal_app) do
    @normal_app ||= Class.new(Onetime::Application::Base) do
      @uri_prefix = '/spec-registry-normal'
      class << self
        attr_accessor :skip
        def should_skip_loading? = skip != false
      end
    end
  end

  let!(:abstract_app) do
    @abstract_app ||= Class.new(Onetime::Application::Base) do
      @uri_prefix = '/spec-registry-abstract'
      @abstract   = true
    end
  end

  let!(:skipped_app) do
    @skipped_app ||= Class.new(Onetime::Application::Base) do
      @uri_prefix = '/spec-registry-skipped'
      def self.should_skip_loading? = true
    end
  end

  before do
    described_class.hard_reset!
    normal_app.skip = false
    [normal_app, abstract_app, skipped_app].each do |klass|
      described_class.register_application_class(klass)
    end
  end

  after do
    normal_app.skip = nil
    described_class.reset!
  end

  describe '.create_mount_mappings' do
    subject(:mappings) do
      described_class.send(:create_mount_mappings)
      described_class.mount_mappings
    end

    it 'maps a concrete, loadable application to its uri_prefix' do
      expect(mappings['/spec-registry-normal']).to eq(normal_app)
    end

    it 'skips abstract classes' do
      expect(mappings).not_to have_key('/spec-registry-abstract')
    end

    it 'skips should_skip_loading? classes (same predicate as reregister_loaded_applications)' do
      expect(mappings).not_to have_key('/spec-registry-skipped')
    end
  end
end
