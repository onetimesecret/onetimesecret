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

        db           = Familia.dbclient(Onetime::Operations::BannerState::DB)
        banner_text  = db.get(Onetime::Operations::BannerState::KEY)
        # Sidecar audience scope; blank/invalid collapses to the safe default so a
        # legacy string-only banner stays off custom domains + recipient pages.
        banner_scope = Onetime::Operations::BannerState.normalize_scope(
          db.get(Onetime::Operations::BannerState::SCOPE_KEY),
        )

        if banner_text && !banner_text.empty?
          OT.li "[init] Global banner (#{banner_scope}): #{banner_text}"
        end

        # Update features runtime state with banner + scope
        Onetime::Runtime.update_features(
          global_banner: banner_text,
          global_banner_scope: banner_scope,
        )
      end
    end
  end
end
