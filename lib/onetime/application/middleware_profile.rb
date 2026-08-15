# lib/onetime/application/middleware_profile.rb
#
# frozen_string_literal: true

#
# Per-application middleware profiles (refactor step 2 of the issue #4170
# middleware consolidation).
#
# A profile is DECLARED DATA: a named, ordered list of component names from
# Onetime::Middleware::Registry. Applications declare a profile at class
# level (`middleware_profile :authenticated_web`) instead of mounting
# middleware imperatively inside environment-conditional blocks. Resolution
# happens per-request-app at build time in Base#build_rack_app, gated by the
# same `site.middleware.<key>` config toggles Onetime::Middleware::Security
# uses — a key absent from config resolves falsy and the component is NOT
# mounted, which keeps this step behavior-neutral until config defaults for
# the profile keys land (step 3).

require_relative '../middleware/registry'

module Onetime
  module Application
    module MiddlewareProfile
      PROFILES = {
        # No extra registry components beyond the universal MiddlewareStack.
        # The default for every application that does not declare otherwise.
        standard: [].freeze,

        # What apps/web/auth/application.rb's production-only block mounts
        # today, in the same order. Step 3 removes that block and adds config
        # defaults so this profile takes over in production.
        authenticated_web: %w[
          Deflater
          ContentSecurityPolicy
          FrameOptions
          HttpOrigin
          IPSpoofing
          PathTraversal
          SessionHijacking
        ].freeze,

        # Semantic marker for loopback-only apps (e.g. Internal::ACME). Same
        # resolution as :standard today; the distinct name declares intent.
        internal: [].freeze,
      }.freeze

      # @param name [Symbol, String] profile name, e.g. :authenticated_web
      # @return [Array<String>] ordered Registry component names
      # @raise [ArgumentError] if the profile name is unknown
      def self.fetch(name)
        PROFILES.fetch(name.to_sym) do
          raise ArgumentError,
            "Unknown middleware profile #{name.inspect} (known: #{PROFILES.keys.inspect})"
        end
      end

      # Resolve a named profile against a Rack builder.
      #
      # Each component's klass/options come from the Registry; mounting is
      # gated by `site.middleware.<key>` exactly like Security's mounts, with
      # matching enable/disable logging (warn on a disabled security-critical
      # component, per Registry.security_critical?).
      #
      # @param name [Symbol, String] profile name
      # @param builder [#use] Rack::Builder (or recorder) to mount onto
      # @return [void]
      def self.apply(name, builder)
        component_names = fetch(name)
        return if component_names.empty?

        settings = Onetime.conf&.dig('site', 'middleware') || {}

        component_names.each do |component_name|
          config = Onetime::Middleware::Registry.fetch(component_name)
          key    = config[:key].to_s

          unless settings[key]
            if Onetime::Middleware::Registry.security_critical?(key)
              OT.lw "[MiddlewareProfile] #{component_name} DISABLED for profile :#{name} (site.middleware.#{key}=false)"
            else
              OT.ld "[MiddlewareProfile] Skipping #{component_name} for profile :#{name} (site.middleware.#{key} not enabled)"
            end
            next
          end

          OT.ld "[MiddlewareProfile] Enabling #{component_name} for profile :#{name} (site.middleware.#{key})"
          builder.use config[:klass], **(config[:options] || {})
        end
      end
    end
  end
end
