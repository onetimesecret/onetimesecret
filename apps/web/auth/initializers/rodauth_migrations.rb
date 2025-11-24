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

      def execute(_context)
        if Onetime.auth_config.advanced_enabled?
          # Require Auth::Migrator only when needed (after config is loaded)
          # apps/web needs to be in $LOAD_PATH already for this to work
          require 'auth/migrator'

          Auth::Migrator.run_if_needed
          Onetime.auth_logger.debug 'Auth application initialized (advanced mode)'
        else
          error_msg = 'Auth application mounted in basic mode - this is a configuration error. ' \
                      'The Auth app is designed for advanced mode only. In basic mode, authentication ' \
                      'is handled by Core app at /auth/*. Check your application registry configuration.'
          Onetime.auth_logger.error error_msg,
            app: 'Auth::Application',
            mode: 'basic',
            expected_mode: 'advanced'
          raise Onetime::Problem, error_msg
        end
      end
    end
  end
end
