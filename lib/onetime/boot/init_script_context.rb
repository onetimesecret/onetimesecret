# lib/onetime/boot/init_script_context.rb

module Onetime
  module Boot
    # Context object that provides a clean interface for init scripts
    # to access configuration and boot options
    #
    class InitScriptContext
      attr_reader :global, :config, :section_key, :options

      def initialize(config, section_key, global, **options)
        @config         = config # mutable
        @section_key    = section_key
        @global         = global # immutable
        @options        = options
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

      def info(message)
        OT.li "[BOOT:#{section_key}] #{message}"
      end

      def debug(message)
        OT.ld "[BOOT:#{section_key}] #{message}"
      end

      def error(message)
        OT.le "[BOOT:#{section_key}] #{message}"
      end
    end
  end
end
