# lib/onetime/initializers.rb

require_relative 'initializers/registry'
require_relative 'initializers/setup_global_secret'   # TODO: Combine into
require_relative 'initializers/setup_rotated_secrets' # setup_secrets
require_relative 'initializers/load_locales'
require_relative 'initializers/connect_databases'
require_relative 'initializers/setup_emailers'
require_relative 'initializers/load_fortunes'
require_relative 'initializers/load_global_banner'
require_relative 'initializers/load_plans'
require_relative 'initializers/configure_truemail'
require_relative 'initializers/configure_domains'
require_relative 'initializers/setup_authentication'
require_relative 'initializers/setup_diagnostics'
require_relative 'initializers/setup_system_settings'
require_relative 'initializers/display_log_banner'

# Alias for brevity in registration
OT::Init = Onetime::Initializers

# Register initializers with their dependencies
# Group 0: No internal dependencies, rely on OT.conf
OT::Init::Registry.register(OT::Init::LoadLocales)
OT::Init::Registry.register(OT::Init::SetupGlobalSecret)
OT::Init::Registry.register(OT::Init::SetupRotatedSecrets)
OT::Init::Registry.register(OT::Init::LoadFortunes)
OT::Init::Registry.register(OT::Init::ConnectDatabases) # Internally handles options[:connect_to_db]

# Group 1: Depend on Group 0 (especially ConnectDatabases)
OT::Init::Registry.register(
  OT::Init::LoadGlobalBanner,
  [OT::Init::ConnectDatabases],
)

OT::Init::Registry.register(
  OT::Init::SetupSystemSettings,
  [OT::Init::ConnectDatabases],
) # Loads OT.sysconfig from DB

# Group 2: Depend on SetupSystemSettings (OT.sysconfig) and others
OT::Init::Registry.register(
  OT::Init::LoadPlans,
  [OT::Init::SetupSystemSettings],
)

OT::Init::Registry.register(
  OT::Init::SetupAuthentication,
  [
    OT::Init::SetupGlobalSecret,
    OT::Init::SetupRotatedSecrets,
    OT::Init::SetupSystemSettings,
  ],
)

OT::Init::Registry.register(
  OT::Init::SetupDiagnostics,
  [OT::Init::SetupSystemSettings],
)

OT::Init::Registry.register(
  OT::Init::ConfigureDomains,
  [OT::Init::SetupSystemSettings],
)

OT::Init::Registry.register(
  OT::Init::ConfigureTruemail,
  [OT::Init::SetupSystemSettings],
)

# Group 3: Depend on Group 2
OT::Init::Registry.register(
  OT::Init::SetupEmailers,
  [
    OT::Init::ConfigureTruemail,
    OT::Init::ConfigureDomains,
    OT::Init::SetupSystemSettings, # Redundant if others list it, but explicit
  ],
)

# Group 4: Finalizers (e.g., logging)
OT::Init::Registry.register(
  OT::Init::DisplayLogBanner, # Depends on a late-stage initializer to ensure it runs last
  [
    OT::Init::SetupEmailers,
  ],
)
