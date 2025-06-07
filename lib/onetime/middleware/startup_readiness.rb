# lib/onetime/middleware/startup_readiness.rb

module Onetime
  module Middleware
    class StartupReadiness
      def initialize(app)
        @app = app
      end

      def call(env)
        if Onetime.ready?
          @app.call(env)
        else
          # Return a specific startup page
          [503,
           {'Content-Type' => 'text/html'},
           ["<html><body> Missing required static configuration. Please check server log and config file for details.</body></html>"]]
        end
      end
    end
  end
end

# lib/onetime.rb
module Onetime
  class << self
    def ready?
      !!@ready
    end

    def mark_ready!
      @ready = true
    end

    # Call this after all configuration is loaded
    def complete_initialization!
      # Load plans
      Plan.load_plans!
      # Load locales and other config
      # ...
      mark_ready!
    end
  end
end
