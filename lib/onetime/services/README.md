## System Design: Init Scripts, Service Providers, and Dynamic Configuration

### Architecture Overview
Your two-phase initialization cleanly separates concerns that Rails conflates:

**Phase 1: Init Scripts** (`etc/init.d/*.rb`)
- Run during config processing (before freeze)
- One script per config section
- Normalize/validate configuration
- Set derived config values
- Cannot start services

**Phase 2: Service Providers** (`lib/onetime/services/system/*.rb`)
- Run after config freeze
- Initialize services using final config
- Register with ServiceRegistry
- Set application state
- **Load dynamic configuration from Redis**

### ServiceRegistry Pattern
Replaces scattered `Onetime.locales`, `Onetime.d9s_enabled` globals:

```ruby
module Onetime::ServiceRegistry
  @providers = Concurrent::Map.new    # Service instances/connections
  @app_state = Concurrent::Map.new    # Runtime state values

  def self.register_provider(name, provider)
  def self.set_state(key, value)      # Used for dynamic config storage
  def self.state(key)                 # Access dynamic config/state
  def self.reload_all(new_config)     # Hot reload capability
end
```

### Dynamic Configuration
- **Static config**: YAML file (database URLs, core settings)
- **Dynamic config**: Redis-stored config sections (interface, mail, limits, etc.) via SystemSettings
- **Merged config**: Combined static + dynamic loaded into ServiceRegistry
- **Unified access**: `Onetime.conf[:key]` for all configuration

```ruby
module Onetime
  def self.conf
    @conf ||= ConfigProxy.new
  end
end

class ConfigProxy
  def [](key)
    ServiceRegistry.state(:merged_config)[key]
  end
end

# Dynamic config provider merges static and dynamic config
def load_dynamic_configuration
  merged_config = merge_static_and_dynamic_config
  ServiceRegistry.set_state(:merged_config, merged_config)
end

def merge_static_and_dynamic_config
  base_config = @static_config.dup
  # SystemSettings.current handles versioning/rollback internally
  dynamic_config = SystemSettings.current.to_onetime_config
  base_config.deep_merge(dynamic_config)
rescue Onetime::RecordNotFound
  base_config  # No dynamic config exists yet
end
```

### Service Provider Types

Service providers are categorized by their primary role in initializing parts of the system and how they interact with the `ServiceRegistry`. The `ServiceProvider` base class defines these core types:

-   **Instance Providers (`TYPE_INSTANCE`)**: These providers are responsible for creating an instance of a service object (e.g., a `LocaleService` object) and then registering that *object* with the `ServiceRegistry`. The application later retrieves this service object to interact with it.
-   **Connection Providers (`TYPE_CONNECTION`)**: These providers focus on configuring external libraries, shared modules, or establishing connections to external systems (e.g., configuring an SMTP mailer library, setting up the primary database connection). They typically register the configured module/class itself or a status indicating its readiness.
-   **Config Providers (`TYPE_CONFIG`)**: These providers process, load, or compute configuration and runtime state, making it available through `ServiceRegistry.set_state(key, value)`. This includes merging dynamic settings (like those from `SystemSettings` in Redis) with static configuration, or deriving application state like feature flags or authentication parameters.

Regardless of type, all providers leverage the `ServiceRegistry` to make their resulting services or state accessible system-wide, avoiding the need for global variables.

**Why Instances, Not Classes?**

Service providers are instantiated during initialization rather than registering their classes directly. This design is crucial because:

1.  **Stateful Management**: Each service provider instance encapsulates its own lifecycle state (`:pending`, `:running`, `:error`), the specific configuration it was started with, and any runtime errors. A class cannot hold this instance-specific, dynamic state.
2.  **Configuration Context**: When a provider's `start` method is called, it receives a configuration object. This object is often stored or used by the *instance* to tailor its setup logic (e.g., an `AuthenticationProvider` instance stores specific colonel lists from the config).
3.  **Lifecycle Operations**: Methods like `start`, `stop`, and `reload` operate on the managed resources of a particular service. An instance is necessary to know *which* specific service's resources to act upon.
4.  **Distinct Roles**: The `ServiceProvider` instance is the *manager* or *orchestrator* for a service. It uses the `ServiceRegistry` to make the actual *service object* (e.g., a mailer client) or *application state* (e.g., locale data) available, not itself.

Basically instances allow each provider to be a self-contained unit responsible for a specific piece of the application's infrastructure or runtime state, complete with its own configuration and lifecycle.

**Future Considerations: Dynamic Orchestration via Self-Registration**

Currently, provider instances are explicitly created and started in a central location (e.g., `Onetime::Services::System.start_all`). To enhance flexibility and further decouple providers, a future evolution could involve:

-   **Class Self-Registration**: `ServiceProvider` classes could automatically register themselves (along with their `name`, `dependencies`, and `priority`) with an orchestrator module when their defining file is loaded by Ruby.
-   **Automated Dependency Resolution**: The orchestrator would then use this registered metadata to dynamically discover all available providers, build a dependency graph, and determine the correct instantiation and startup order using a topological sort.

This approach would allow new providers to be added to the system simply by creating their class file, without needing to modify a central list. The system would dynamically adapt its startup sequence based on the declared needs of each provider, making it more robust and easier to extend.


#### Example Service Provider Implementation
```ruby
class EmailerProvider < ServiceProvider
  def start
    # Capture config outside blocks to avoid context issues
    mail_config = Onetime.conf[:mail]

    # Configure mailer based on provider type
    case mail_config[:provider]
    when 'smtp'
      SMTPMailer.setup(mail_config[:connection])
      register_provider(:emailer, SMTPMailer)
    when 'sendgrid'
      SendgridMailer.setup(mail_config[:api_key])
      register_provider(:emailer, SendgridMailer)
    end

    set_state(:emailer_configured, true)
  rescue => ex
    Onetime.le "Failed to configure emailer: #{ex.message}"
    # Graceful degradation - continue without email capability
  end

  def stop
    provider(:emailer)&.cleanup if has_provider?(:emailer)
    clear_provider(:emailer)
  end
end
```

### Orchestration Flow
```ruby
def boot!
  run_init_scripts(config)           # Phase 1: Config normalization
  freeze_config()
  Onetime::Services::System.start_all(config)  # Phase 2: Service providers
end

def Onetime::Services::System.start_all(config)
  start_database_connections(config)  # Essential connections first
  load_dynamic_configuration()        # Merge static + dynamic config
  start_remaining_providers(config)   # Other services
end
```

### Configuration Access Patterns
```ruby
# All config accessed via unified interface:
Onetime.conf[:storage]              # From static YAML
Onetime.conf[:user_interface]       # Merged static + dynamic (SystemSettings)
Onetime.conf[:mail]                 # Merged configuration for email settings

# Service provider access:
ServiceRegistry.provider(:emailer)   # Get configured mailer instance
ServiceRegistry.state(:locales)     # Get runtime state values
ServiceRegistry.has_provider?(:db)  # Check if provider is registered

# Hot reload after admin UI changes:
ServiceRegistry.reload_dynamic_config  # Re-merges and updates
```

### Service Provider Best Practices
- **Capture config outside blocks**: Avoid `self` context issues in configuration blocks
- **Graceful degradation**: Handle missing config sections with defaults or skip non-essential services
- **Clear error messages**: Log configuration issues with context using `Onetime.le`
- **Idempotent operations**: Support multiple start/stop cycles
- **Resource cleanup**: Always implement proper `stop` methods

### How This Differs From Rails (For Experienced Rails Developers)

Rails' initialization model works well for most applications, but this system addresses specific needs around configuration management and service lifecycle that emerge in certain contexts.

**Explicit Config Finalization**
Rails allows configuration changes throughout initialization via `Rails.application.config` modifications in initializers. This system provides a clear freeze point where you know configuration becomes immutable—helpful when you need predictable config state or are debugging complex initialization sequences.

**Runtime Config Changes**
Rails' typical pattern requires restart for configuration changes, which works fine for most deployments. This ServiceRegistry pattern enables hot-swapping config (especially dynamic config from admin UIs) without file changes or restarts—valuable for production systems where restarts are expensive or when non-technical users need to modify settings.

**Centralized Service Registry**
Rails applications often end up with service instances scattered across `Rails.application.config`, custom initializers, and global variables. ServiceRegistry centralizes these into a single lookup mechanism, which can simplify service management in applications with many external integrations.

**Explicit Dependency Ordering**
Rails initializers use alphabetical ordering, often leading to filename prefixes for dependency control. This two-phase approach separates config processing from service startup, making dependencies explicit rather than implicit—useful for complex applications with intricate service interdependencies.

**Graceful Service Degradation**
Rails typically boots completely or fails completely. Service providers here can fail independently while allowing the application to continue—beneficial for applications where some services are optional or when you want to start in a degraded state rather than fail completely.

**Service Lifecycle Management**
Rails doesn't provide standard patterns for service cleanup or restart. The ServiceProvider pattern with explicit `start`/`stop` methods enables operations like health checks, graceful shutdowns, or restarting individual services—helpful for long-running processes or complex service management needs.

**Unified Configuration Interface**
This system presents all configuration through a single interface regardless of source (YAML, database, computed values), whereas Rails applications often require knowing where each config value lives. This can simplify config access in applications with multiple configuration sources.

### Debugging and Monitoring
```ruby
# Service status inspection
ServiceRegistry.providers.keys        # List all registered providers
ServiceRegistry.state.keys           # List all state values

# Configuration debugging
Onetime.conf.debug_dump              # Show merged configuration source
```

This architecture enables config reloading without restart while maintaining cleaner boundaries than Rails' single-phase approach. Dynamic configuration integrates seamlessly through the existing ServiceRegistry pattern, with SystemSettings handling versioning complexity internally. The two-phase initialization and service provider pattern provides better error handling, debugging capabilities, and operational visibility than traditional Rails initializers.
