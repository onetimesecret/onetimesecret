# lib/onetime/boot/init_script_context.rb

require 'extentions/flexible_key_access'

module Onetime
  module Boot
    # Context object that provides a clean interface for init scripts
    # to access configuration and boot options
    #
    # To exit from a script use `abort`. e.g. `abort "Stop what you are doing"`
    #
    # NOTE: Scripts must using strings when accessing global, config, options.
    #
    # DEBUGGING: To debug init scripts with access to all instance variables,
    # add a breakpoint here in initialize() rather than in the script itself.
    # This gives you access to @config, @global, @section_key, @options, etc.
    #
    # To target a specific script, use: `binding.pry if section?('section_key')`
    #
    class InitScriptContext
      attr_reader :global, :config, :section_key, :options

      def initialize(config, section_key, global, **options)
        @config         = config # mutable
        @section_key    = section_key
        @global         = global # immutable
        @options        = options.extend(Extensions::FlexibleKeyAccess)
      end

      # Helper methods available to init scripts
      def instance
        options[:instanceid]
      end

      def mode
        options[:mode]
      end

      def utils
        OT::Configurator::Utils
      end

      def connect_to_db?
        options[:connect_to_db]
      end

      def section?(guess)
        section_key.to_s.eql?(guess)
      end

      def debug?
        OT.debug?
      end

      def info_log(path)
        debug "Running #{section_key} script"
        pretty_path = Onetime::Utils.pretty_path(path)
        debug "Script path: #{pretty_path}"
        debug "Instance: #{instance}, Mode: #{mode}, Connect to DB: #{connect_to_db?}"
      end

      def info(message)
        OT.li "[BOOT:#{section_key}] #{message}"
      end

      def warn(message)
        OT.lw "[BOOT:#{section_key}] #{message}"
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
