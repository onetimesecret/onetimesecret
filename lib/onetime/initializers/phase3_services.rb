# lib/onetime/initializers/phase3_services.rb

require_relative 'setup_diagnostics'

module Onetime
  module Initializers

    def run_phase3_initializers
      OT.ld 'Phase 3 Initializers'
      setup_diagnostics     # Uses merged OT.conf[:diagnostics]
    end

  end
end
