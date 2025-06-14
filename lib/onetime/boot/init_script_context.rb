# lib/onetime/boot/init_script_context.rb

module Onetime
  module Boot
    # Context object that provides a clean interface for init scripts
    # to access configuration and boot options
    #
    # Single Responsibility**: Configurator loads/validates config. # InitScriptContext executes initialization logic - that's Boot's domain.
    #
    # 2. **Dependencies**: It requires boot-time context (`mode`, `instance`, # `connect_to_db`) that only Boot knows about.
    #
    # 3. **Temporal coupling**: Init scripts run AFTER configuration is loaded # and frozen, during the boot sequence.
    #
    # 4. **Cohesion**: The logging methods (`[INIT:section]`) and execution # context are boot concerns, not config concerns.
    #
    # 5. **Purpose**: It's bridging configuration TO initialization, which is # Boot's job.
    class InitScriptContext
      attr_reader :config, :section_config, :section_key, :options

      def initialize(config, section_key, **options)
        @config = config
        @section_key = section_key
        @section_config = config[section_key]
        @options = options
      end

      # Provide a binding context for script evaluation
      def script_binding
        binding
      end

      # Helper methods available to init scripts
      def instance
        options[:instance]
      end

      def mode
        options[:mode]
      end

      def connect_to_db?
        options[:connect_to_db]
      end

      def debug?
        OT.debug?
      end

      def log_info(message)
        OT.li "[INIT:#{section_key}] #{message}"
      end

      def log_debug(message)
        OT.ld "[INIT:#{section_key}] #{message}"
      end

      def log_error(message)
        OT.le "[INIT:#{section_key}] #{message}"
      end
    end
  end
end
