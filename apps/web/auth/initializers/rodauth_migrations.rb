# apps/web/auth/initializers/rodauth_migrations.rb
#
# frozen_string_literal: true

module Auth
  module Initializers
    # Run Rodauth database migrations
    #
    # Ensures Rodauth database tables exist before the Router class loads.
    # Critical because Rodauth validates features during plugin load.
    class RodauthMigrations < Onetime::Boot::Initializer
      @depends_on = [:database]
      @provides = [:rodauth_schema]

      def should_skip?
        # Skip in simple auth mode
        return true unless Onetime.auth_config.full_enabled?

        # Skip for job workers - they don't need database migrations
        # and connecting before Sneakers forks causes SQLite warnings.
        # Check if we're running a jobs command by looking at ARGV.
        return true if jobs_command?

        false
      end

      private

      def jobs_command?
        ARGV.any? { |arg| arg == 'jobs' }
      end

      def execute(_context)
        # Require Auth::Migrator only when needed (after config is loaded)
        # apps/web needs to be in $LOAD_PATH already for this to work
        require 'auth/migrator'

        Auth::Migrator.run_if_needed
        Onetime.auth_logger.debug 'Auth application initialized (full mode)'
      end
    end
  end
end
