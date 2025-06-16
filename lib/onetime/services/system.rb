# lib/onetime/services/system.rb

require 'onetime/services/service_provider'
require 'onetime/services/config_proxy'

# Previously OT.globals:
# :d9s_enabled, :i18n_enabled, :locales,
# :supported_locales, :default_locale, :fallback_locale, :global_banner,
# :rotated_secrets, :emailer, :first_boot, :global_secret

module Onetime
  module Services
    module System
      extend self

      # Load system services dynamically
      Dir[File.join(File.dirname(__FILE__), 'system', '*.rb')].each do |file|
        next if file.match?(/[A-Z_-]+\.rb/) # skip UPPER_CASE.rb files

        OT.ld "[system] Loading #{file}"
        require_relative file
      end

      # Start all system services using service provider orchestration
      def start_all(config, connect_to_db: true)
        OT.li '[BOOT] Starting system services...'

        # Phase 1: Essential connections first
        if connect_to_db
          connect_databases(config)
        else
          OT.ld '[BOOT] Skipping database connections'
        end

        # Phase 2: Dynamic configuration provider (high priority)
        start_dynamic_config_provider(config)

        # Phase 3: Other service providers
        start_remaining_providers(config)

        OT.li '[BOOT] System services started successfully'
      end

      private

      ##
      # Start dynamic configuration provider early in the sequence
      def start_dynamic_config_provider(config)
        return unless defined?(System::DynamicConfigProvider)

        OT.ld '[BOOT] Starting dynamic configuration provider...'
        provider = System::DynamicConfigProvider.new
        provider.start_internal(config)
        ServiceRegistry.register(:dynamic_config, provider)
      end

      ##
      # Start remaining service providers after dynamic config is loaded
      def start_remaining_providers(config)
        # Legacy method calls - TODO: Convert these to service providers
        configure_truemail(config) if defined?(Truemail)
        prepare_emailers(config)
        load_locales(config)
        setup_authentication(config)

        OT.ld '[BOOT] Legacy service initialization completed'
      end
    end
  end
end
