# lib/onetime/initializers/check_global_banner.rb

module Onetime
  module Initializers
    module CheckGlobalBanner

      def self.run(options = {})
        # Skip if database connection is disabled
        return unless options[:connect_to_db]

        global_banner = Familia.redis(0).get('global_banner')
        OT.instance_variable_set(:@global_banner, global_banner)
        OT.li "Global banner: #{global_banner}" if global_banner
        OT.ld "[initializer] Global banner checked"
      end

    end
  end
end
