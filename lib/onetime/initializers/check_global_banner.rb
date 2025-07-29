# lib/onetime/initializers/check_global_banner.rb
# lib/onetime/initializers/check_global_banner.rb
module Onetime
  module Initializers
    attr_reader :global_banner

    def check_global_banner
      @global_banner = Familia.redis(0).get('global_banner')
      OT.li "Global banner: #{OT.global_banner}" if global_banner
    end
  end
end
