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
    #
    class CheckGlobalBanner < Onetime::Boot::Initializer
      @depends_on = [:database]
      @provides   = [:banner]
      @optional   = true

      def execute(_context)
        banner_text = Familia.dbclient(0).get('global_banner')

        if banner_text && !banner_text.empty?
          OT.li "[init] Global banner: #{banner_text}"
        end

        # Update features runtime state with banner
        Onetime::Runtime.update_features(global_banner: banner_text)
      end
    end
  end
end
