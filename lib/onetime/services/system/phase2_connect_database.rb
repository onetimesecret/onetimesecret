# lib/onetime/initializers/phase2_connect_database.rb

require_relative 'connect_databases'
require_relative 'merge_config'

module Onetime
  module Initializers
    attr_reader :global_banner

    def run_phase2_initializers
      OT.ld 'Phase 2 Initializers'
      # Load database configuration
      # load_database_config
      # Merge configuration
      # merge_config
      connect_databases
      merge_config
      setup_authentication   # Uses merged OT.conf[:site][:authentication]
      check_global_banner    # Uses merged OT.conf
      # TODO: Where or when do we replace OT.conf?
    end

    def check_global_banner
      @global_banner = Familia.redis(0).get('global_banner')
      OT.li "Global banner: #{OT.global_banner}" if global_banner
    end
  end
end
