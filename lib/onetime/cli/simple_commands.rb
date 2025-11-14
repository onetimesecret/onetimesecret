# lib/onetime/cli/simple_commands.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # Version command
    class VersionCommand < DelayBootCommand
      desc 'Display version information'

      def call(**)
        puts format('Onetime %s', OT::VERSION.inspect)
      end
    end

    # Load path command
    class LoadPathCommand < DelayBootCommand
      desc 'Lists the first 5 paths in the load path'

      def call(**)
        puts $LOAD_PATH[0...5]
      end
    end

    # Console command
    class ConsoleCommand < DelayBootCommand
      desc 'Ruby irb with Onetime preloaded'

      option :delay_boot, type: :boolean, default: false, aliases: ['B'],
             desc: 'Bring up the console without initializing'

      def call(delay_boot: false, **)
        cmd = format('irb -I%s -ronetime/console', File.join(Onetime::HOME, 'lib'))
        OT.ld cmd

        # Set the boot env var for the console process
        ENV['DELAY_BOOT'] = delay_boot.to_s
        Kernel.exec(cmd)
      end
    end

    # Help command
    class HelpCommand < DelayBootCommand
      desc 'Display help information'

      argument :topic, type: :string, required: false, desc: 'Help topic (e.g., logging)'

      def call(topic: nil, **)
        case topic
        when 'logging', 'logs'
          print_logging_help
        else
          print_general_help
        end
      end

      private

      def print_logging_help
        puts <<~HELP
          ═══════════════════════════════════════════════════════════════════════
          Logging Configuration and Environment Variables
          ═══════════════════════════════════════════════════════════════════════

          Onetime uses SemanticLogger with strategic categories for operational
          monitoring and debugging. Configuration is loaded from etc/logging.yaml
          with environment variable overrides for flexible control.

          LOGGING CATEGORIES
          ══════════════════

          Auth     - Authentication/authorization flows
          Session  - Session lifecycle management
          HTTP     - HTTP requests, responses, and middleware
          Familia  - Redis operations via Familia ORM
          Otto     - Otto framework operations
          Rhales   - Rhales template rendering
          Sequel   - Database queries and operations
          Secret   - Secret lifecycle (create, view, burn)
          App      - Default fallback for application-level logging

          ENVIRONMENT VARIABLES (Applied in Order)
          ═════════════════════════════════════════

          1. LOG_LEVEL - Sets global default level for unconfigured loggers
             Example: LOG_LEVEL=warn bin/ots server
             Effect:  Changes default_level, respects individual logger config

          2. ONETIME_DEBUG - Quick "debug everything by default" flag
             Example: ONETIME_DEBUG=1 bin/ots server
             Effect:  Sets default_level to debug, individual loggers still
                      respect their configured levels from etc/logging.yaml

          3. DEBUG_LOGGERS - Fine-grained per-logger control (overrides YAML)
             Example: DEBUG_LOGGERS=Auth:debug,Secret:trace,Familia:warn
             Effect:  Sets specific logger levels, overriding YAML configuration

          4. DEBUG_* - Individual quick flags (override YAML config)
             DEBUG_AUTH=1      - Set Auth logger to debug
             DEBUG_SESSION=1   - Set Session logger to debug
             DEBUG_HTTP=1      - Set HTTP logger to debug
             DEBUG_SECRET=1    - Set Secret logger to debug
             DEBUG_SEQUEL=1    - Set Sequel logger to debug (SQL at trace)
             DEBUG_APP=1       - Set App logger to debug

          EXTERNAL LIBRARY FLAGS
          ═══════════════════════

          FAMILIA_DEBUG=1           - Familia's built-in debug flag
          FAMILIA_SAMPLE_RATE=0.01  - Familia command sampling (0.0-1.0)
          OTTO_DEBUG=1              - Otto framework debug flag

          USAGE EXAMPLES
          ═══════════════

          Debug everything:
            ONETIME_DEBUG=1 bin/ots server

          Debug only Auth and Session:
            DEBUG_AUTH=1 DEBUG_SESSION=1 bin/ots server

          Fine-tuned logging for Auth (trace) and Secret (debug):
            DEBUG_LOGGERS=Auth:trace,Secret:debug bin/ots server

          Override default level but respect individual logger config:
            LOG_LEVEL=warn bin/ots server

          Combine multiple approaches:
            LOG_LEVEL=info DEBUG_AUTH=1 DEBUG_LOGGERS=Sequel:trace bin/ots server

          Production with reduced noise:
            LOG_LEVEL=warn DEBUG_LOGGERS=Familia:info,Otto:info bin/ots server

          LEVEL HIERARCHY
          ════════════════

          trace < debug < info < warn < error < fatal

          Lower levels include all higher levels. Setting level to 'warn' will
          show warn, error, and fatal messages.

          CONFIGURATION FILE
          ═══════════════════

          Edit etc/logging.yaml to set default logger levels. Environment
          variables provide runtime overrides without modifying the file.

          For more information, see etc/logging.yaml comments.
          ═══════════════════════════════════════════════════════════════════════
        HELP
      end

      def print_general_help
        puts <<~HELP
          Usage: ots help [topic]

          Available topics:
            logging    - Logging configuration and environment variables

          For command-specific help:
            ots COMMAND --help

          To see all commands:
            ots --help
        HELP
      end
    end

    # Register simple commands
    register 'version', VersionCommand
    register 'build', VersionCommand  # Alias for version
    register 'load-path', LoadPathCommand
    register 'console', ConsoleCommand
    register 'help', HelpCommand
  end
end
