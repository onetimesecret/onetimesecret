# frozen_string_literal: true

require 'json'

module Onetime
  module Authorization
    # The client reads this same manifest. Values under capabilities name the
    # lowest membership role that receives the capability by default.
    module Registry
      manifest = JSON.parse(File.read(File.expand_path('../../../src/schemas/contracts/authorization-registry.json', __dir__)))
      defaults = manifest.fetch('capabilities')
      ranks    = { 'member' => 0, 'admin' => 1, 'owner' => 2 }

      FEATURES          = manifest.fetch('features').keys.to_set.freeze
      CAPABILITIES      = defaults.keys.to_set.freeze
      ROLE_CAPABILITIES = ranks.to_h do |role, rank|
        [role, defaults.select { |_, minimum| ranks.fetch(minimum) <= rank }.keys.to_set.freeze]
      end.freeze
      sections = { 'features' => 'feature', 'capabilities' => 'capability', 'account' => 'account', 'reserved' => 'reserved' }
      KINDS    = sections.flat_map do |section, kind|
        manifest.fetch(section).keys.map { |name| [name, kind] }
      end.to_h.freeze

      def self.features          = FEATURES
      def self.capabilities      = CAPABILITIES
      def self.role_capabilities = ROLE_CAPABILITIES
      def self.feature?(name)    = FEATURES.include?(name.to_s)
      def self.capability?(name) = CAPABILITIES.include?(name.to_s)
      def self.kind(name)        = KINDS[name.to_s]
    end
  end
end
