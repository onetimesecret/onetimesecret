# lib/onetime/services/system.rb

require_relative 'service_provider'
require_relative 'config_proxy'
require_relative 'service_registry'

module Onetime
  module Services
    module System
      extend self

      # Load system services dynamically
      Dir[File.join(File.dirname(__FILE__), 'system', '*.rb')].each do |file|
        next if file.match?(/[A-Z_-]+\.rb/) # skip UPPER_CASE.rb files

        # Pretty path is the relative path to the provider file
        pretty_path = Onetime::Utils.pretty_path(file)
        OT.ld "[system] Loading #{pretty_path}"

        require_relative file
      end

      # Start all system services using service provider orchestration
      def start_all(config, connect_to_db: true)
        OT.li "[BOOT.system] Starting system services with frozen config (#{config.frozen?})..."

        providers = []

        # Phase 1: Essential connections first
        if connect_to_db
          providers << System::ConnectDatabases.new
        else
          OT.li '[BOOT.system] Skipping database connections and remaining providers'
          return
        end

        # Phase 2: Dynamic configuration provider (high priority)
        providers << System::DynamicConfig.new

        # Phase 3: Core service providers
        providers << System::TruemailProvider.new
        providers << System::EmailerProvider.new
        providers << System::LocaleProvider.new
        providers << System::AuthenticationProvider.new

        # Phase 4: Information display (runs last)
        providers << System::LogBannerProvider.new

        # Start providers in priority order
        OT.ld "[BOOT.system] Sorting #{providers.size} providers by priority"
        providers.sort_by!(&:priority)
        providers.each do |provider|
          OT.ld "[BOOT.system] Starting #{provider.name} provider"
          ServiceRegistry.register_provider(provider.name, provider)
          provider.start_internal(config)
        end


        OT.li '[BOOT.system] System services started successfully'
      end

    end

    # NOTE: To remove, delete this line and the legacy_globals.rb file.
    require_relative 'legacy_globals'
  end
end
