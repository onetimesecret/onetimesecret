# lib/onetime/ready.rb

module Onetime
  class << self
    def ready?
      !!@ready
    end

    def not_ready?
      !ready?
    end

    def not_ready!
      @ready = false
    end

    def mark_ready!
      @ready = true
    end

    # Call this after all configuration is loaded
    def complete_initialization!
      # Load plans
      Plan.load_plans!

      # TODO

      mark_ready!
    end
  end
end
