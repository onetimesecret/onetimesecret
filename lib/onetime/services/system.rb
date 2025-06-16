# lib/onetime/services/system.rb

require 'onetime/services/service_registry'

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
        OT.ld "[system] Loading #{file}"
        require_relative file
      end

      # Start all system services
      def start_all(config, connect_to_db: true)
        OT.li '[BOOT] Starting system services...'

        # Start database services
        if connect_to_db
          connect_databases(config)
        else
          OT.ld '[BOOT] Skipping database connections'
        end

        # Start other services
        configure_truemail(config) if defined?(Truemail)
        prepare_emailers(config)
        load_locales(config)
        setup_authentication(config)
        # Add other service initializers

        OT.li '[BOOT] System services started successfully'
      end
    end
  end
end
