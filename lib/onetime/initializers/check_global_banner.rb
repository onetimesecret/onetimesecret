# lib/onetime/initializers/check_global_banner.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # CheckGlobalBanner initializer
    #
    # Checks Redis for a global banner message to display across the application.
    # This allows administrators to set site-wide announcements dynamically.
    #
    # Runtime state set:
    # - Onetime::Runtime.features.global_banner
    # - Onetime::Runtime.features.global_banner_scope
    #
    class CheckGlobalBanner < Onetime::Boot::Initializer
      @depends_on = [:database]
      @provides   = [:banner]
      @optional   = true

      def execute(_context)
        require 'onetime/operations/banner'

        # Read through the shared BannerState path: one MGET snapshot folded
        # into a single Features update (the same code the TTL re-read uses),
        # so even the boot read can never pair banner content with a scope
        # from a different banner. Blank/invalid scope collapses to the safe
        # default, keeping legacy string-only banners off custom domains +
        # recipient pages. Fail-soft: a dead Redis logs and leaves the nil
        # defaults in place (this initializer is @optional).
        Onetime::Operations::BannerState.refresh!

        banner_text  = Onetime::Runtime.features.global_banner
        banner_scope = Onetime::Runtime.features.global_banner_scope
        if banner_text && !banner_text.empty?
          OT.li "[init] Global banner (#{banner_scope}): #{banner_text}"
        end

        # Stamp the TTL re-read clock: this boot read IS a fresh read, so the
        # first request should serve it instead of immediately re-hitting Redis.
        Onetime::Operations::BannerState.prime_cache!
      end
    end
  end
end
