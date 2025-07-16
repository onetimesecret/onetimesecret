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
        OT.ld "[BOOT.system] Starting system services with frozen config (#{config.frozen?})..."

        providers = []

        # TODO: We can handle this a lot better by allowing the provider classes
        # to self-register, giving us the priority and dependencies. Instead of
        # just pulling the plug here, we could still be running the providers
        # that aren't depdendent on the database connection.
        if connect_to_db
          providers << System::ConnectDatabases.new
        else
          OT.ld '[BOOT.system] Skipping database connections and remaining providers'
          return
        end

        # The order here is arbitrary. We sort them by priority next.
        providers << System::SetupDiagnostics.new
        # providers << System::CheckGlobalBanner.new
        providers << System::FirstBoot.new
        providers << System::RuntimeConfigService.new
        providers << System::TruemailProvider.new
        providers << System::PrepareEmailers.new
        providers << System::LocaleProvider.new
        providers << System::AuthenticationProvider.new
        providers << System::PrintBootReceipt.new

        sort_by_priority_and_start(providers, config)

        OT.ld '[BOOT.system] System services started successfully'
      end

      private

      def sort_by_priority_and_start(providers, config)
        OT.ld "[BOOT.system] Sorting #{providers.size} providers by priority"
        providers.sort_by!(&:priority)
        providers.each do |provider|
          OT.ld "[BOOT.system] Starting #{provider.name} provider"
          ServiceRegistry.register_provider(provider.name, provider)
          provider.start_internal(config)
        end
      end
    end

    # NOTE: To remove, delete this line and the legacy_globals.rb file.
    require_relative 'legacy_globals'
  end
end
