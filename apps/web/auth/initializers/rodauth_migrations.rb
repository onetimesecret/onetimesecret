# apps/web/auth/initializers/rodauth_migrations.rb
#
# frozen_string_literal: true

# Run Rodauth database migrations
#
# Self-registering initializer that ensures Rodauth database tables exist
# before the Router class loads. This is critical because Rodauth validates
# features during plugin load, requiring tables to be present.
#
# Depends on: :database (Sequel connection must be established)
# Provides: :rodauth_schema capability
#
Auth::Application.initializer(
  :rodauth_migrations,
  description: 'Run Rodauth database migrations',
  depends_on: [:database],
  provides: [:rodauth_schema]
) do |_ctx|
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
