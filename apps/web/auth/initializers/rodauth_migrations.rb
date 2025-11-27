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
        !Onetime.auth_config.full_enabled?
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
