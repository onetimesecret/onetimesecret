# lib/onetime/initializers/run_migrations.rb


module Onetime
  module Initializers
    def run_migrations
      # Run migrations BEFORE loading the Router class
      # This ensures database tables exist when Rodauth validates features during plugin load
      if Onetime.auth_config.advanced_enabled?

        Auth::Migrator.run_if_needed
        Onetime.auth_logger.debug 'Auth database migrations completed before router load'

      end
    rescue StandardError => ex
      Onetime.auth_logger.error 'Auth database migrations failed before router load', exception: ex
      raise ex if Onetime.development?
    end
  end
end
