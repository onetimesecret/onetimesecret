# lib/onetime/runtime/features.rb
#
# frozen_string_literal: true

module Onetime
  module Runtime
    # Optional features runtime state
    #
    # Holds configuration for optional features like custom domains, global
    # banners, and fortunes set during boot. This state is immutable after
    # initialization and thread-safe.
    #
    # Set by: ConfigureDomains, CheckGlobalBanner, LoadFortunes initializers
    #
    # Default banner audience scope when none is stored. Mirrors
    # Operations::BannerState::DEFAULT_SCOPE (kept as a literal here to avoid a
    # boot-time require cycle: this Data is defined before the ops load).
    DEFAULT_BANNER_SCOPE = 'no_recipient'

    Features = Data.define(
      :domains_enabled,      # Whether custom domains feature is enabled
      :global_banner,        # Optional global banner message from Redis
      :global_banner_scope,  # Banner audience scope (see Operations::BannerState)
      :fortunes,             # Array of fortune messages
    ) do
      # Factory method for default state
      #
      # @return [Features] Features state with safe defaults
      #
      def self.default
        new(
          domains_enabled: false,
          global_banner: nil,
          global_banner_scope: DEFAULT_BANNER_SCOPE,
          fortunes: [],
        )
      end

      # Check if domains feature is enabled
      #
      # @return [Boolean] true if custom domains enabled
      #
      def domains?
        domains_enabled
      end

      # Check if global banner is set
      #
      # @return [Boolean] true if banner exists
      #
      def banner?
        !global_banner.nil? && !global_banner.empty?
      end

      # Get a random fortune message
      #
      # @return [String, nil] Random fortune or nil if none available
      #
      def random_fortune
        return nil if fortunes.empty?

        fortunes.sample
      end

      # Get number of available fortunes
      #
      # @return [Integer] Count of fortune messages
      #
      def fortune_count
        fortunes.size
      end
    end
  end
end
