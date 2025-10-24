# lib/onetime/initializers/run_migrations.rb


module Onetime
  module Initializers
    def run_migrations
      # Run migrations BEFORE loading the Router class
      # This ensures database tables exist when Rodauth validates features during plugin load
      if Onetime.auth_config.advanced_enabled?
        # Require Auth::Migrator only when needed (after config is loaded)
        #
        # apps/web needs to be in $LOAD_PATH already for this to work
        require 'auth/migrator'

        Auth::Migrator.run_if_needed
        Onetime.auth_logger.debug 'Auth database migrations completed before router load'
      end

    rescue StandardError => ex
      Onetime.auth_logger.error 'Auth database migrations failed before router load', exception: ex
      raise ex if Onetime.development?
    end
  end
end
