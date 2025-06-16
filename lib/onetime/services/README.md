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
- **Instance providers**: Return objects (LocaleService instance)
- **Connection providers**: Configure modules (EmailerService sets up mailer)
- **Dynamic config provider**: Merges SystemSettings with static config into ServiceRegistry
- All register via ServiceRegistry instead of polluting Onetime namespace

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
Onetime.conf[:storage]    # From static YAML
Onetime.conf[:user_interface]       # Merged static + dynamic (SystemSettings) via ServiceRegistry.state[...]
Onetime.conf[:locales]         # Service state

# Hot reload after admin UI changes:
ServiceRegistry.reload_dynamic_config  # Re-merges and updates
```

### Benefits Over Rails
- Clear config finalization point
- Hot reload capability via ServiceRegistry
- No global state pollution
- Explicit service lifecycle management
- Better separation of concerns than Rails initializers
- **Unified config interface hiding static/dynamic complexity**
- **SystemSettings versioning/rollback abstracted away from service layer**

This architecture enables config reloading without restart while maintaining cleaner boundaries than Rails' single-phase approach. Dynamic configuration integrates seamlessly through the existing ServiceRegistry pattern, with SystemSettings handling versioning complexity internally.
