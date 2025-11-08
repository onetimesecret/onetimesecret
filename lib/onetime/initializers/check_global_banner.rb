# lib/onetime/initializers/check_global_banner.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    attr_reader :global_banner

    def check_global_banner
      @global_banner = Familia.dbclient(0).get('global_banner')
      OT.li "[init] Global banner: #{OT.global_banner}" if global_banner
    end
  end
end
