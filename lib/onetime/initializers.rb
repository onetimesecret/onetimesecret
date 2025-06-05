# lib/onetime/initializers.rb

require_relative 'initializers/registry'
require_relative 'initializers/set_global_secret'   # TODO: Combine into
require_relative 'initializers/set_rotated_secrets' # set_secrets
require_relative 'initializers/load_locales'
require_relative 'initializers/connect_databases'
require_relative 'initializers/prepare_emailers'
require_relative 'initializers/load_fortunes'
require_relative 'initializers/check_global_banner'
require_relative 'initializers/load_plans'
require_relative 'initializers/configure_truemail'
require_relative 'initializers/configure_domains'
require_relative 'initializers/setup_authentication'
require_relative 'initializers/setup_diagnostics'
require_relative 'initializers/setup_system_settings'
require_relative 'initializers/print_log_banner'

# Alias for brevity in registration
Init = Onetime::Initializers
Registry = Init::Registry

# Register initializers with their dependencies
# Group 0: No internal dependencies, rely on OT.conf
Registry.register(Init::LoadLocales)
Registry.register(Init::SetGlobalSecret)
Registry.register(Init::SetRotatedSecrets)
Registry.register(Init::LoadFortunes)
Registry.register(Init::ConnectDatabases) # Internally handles options[:connect_to_db]

# Group 1: Depend on Group 0 (especially ConnectDatabases)
Registry.register(Init::CheckGlobalBanner, depends_on: [Init::ConnectDatabases])
Registry.register(Init::SetupSystemSettings, depends_on: [Init::ConnectDatabases]) # Loads OT.sysconfig from DB

# Group 2: Depend on SetupSystemSettings (OT.sysconfig) and others
Registry.register(Init::LoadPlans, depends_on: [Init::SetupSystemSettings])
Registry.register(Init::SetupAuthentication, depends_on: [
                    Init::SetGlobalSecret,
                    Init::SetRotatedSecrets,
                    Init::SetupSystemSettings,
                  ])
Registry.register(Init::SetupDiagnostics, depends_on: [Init::SetupSystemSettings])
Registry.register(Init::ConfigureDomains, depends_on: [Init::SetupSystemSettings])
Registry.register(Init::ConfigureTruemail, depends_on: [Init::SetupSystemSettings])

# Group 3: Depend on Group 2
Registry.register(Init::PrepareEmailers, depends_on: [
                    Init::ConfigureTruemail,
                    Init::ConfigureDomains,
                    Init::SetupSystemSettings, # Redundant if others list it, but explicit
                  ])

# Group 4: Finalizers (e.g., logging)
Registry.register(Init::PrintLogBanner, depends_on: [ # Depends on a late-stage initializer to ensure it runs last
                    Init::PrepareEmailers,
                  ])
