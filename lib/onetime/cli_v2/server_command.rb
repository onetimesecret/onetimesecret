# lib/onetime/cli_v2/server_command.rb
#
# frozen_string_literal: true

#
# CLI command for running the web server (Puma or Thin)
#
# Supply options or a config file path but not both.
#
# Usage:
#   ots server [options] [configpath]
#
# Options:
#   -s, --server TYPE       Server type: puma or thin (default: puma)
#   -p, --port PORT         Port to bind to (default: 7143)
#   -e, --environment ENV   Environment to run in (default: development)
#   -t, --threads MIN:MAX   Thread pool size for Puma (default: 2:4)
#   -w, --workers COUNT     Number of workers for Puma (default: 0)
#   -b, --bind ADDRESS      Bind address for Thin (default: 0.0.0.0)
#
# @see https://github.com/puma/puma/blob/v7.1.0/lib/rack/handler/puma.rb
# @see https://github.com/macournoyer/thin/blob/v2.0.1/lib/thin/rackup/handler.rb
#

require 'rackup'

module Onetime
  module CLI
    module V2
      class ServerCommand < DelayBootCommand
        desc 'Start the web server (Puma or Thin)'

        argument :config_file, type: :string, required: false, desc: 'Path to server config file'

        option :server, type: :string, default: 'puma', aliases: ['s'], desc: 'Server type: puma or thin'
        option :port, type: :integer, default: 7143, aliases: ['p'], desc: 'Port to bind to'
        option :environment, type: :string, default: 'development', aliases: ['e'], desc: 'Environment to run in'
        option :threads, type: :string, default: '2:4', aliases: ['t'], desc: 'Thread pool size for Puma'
        option :workers, type: :integer, default: 0, aliases: ['w'], desc: 'Number of workers for Puma'
        option :bind, type: :string, default: '127.0.0.1', aliases: ['b'], desc: 'Bind address'

        def call(config_file: nil, server: 'puma', port: 7143, environment: 'development',
                 threads: '2:4', workers: 0, bind: '127.0.0.1', **)
          has_options = port != 7143 || threads != '2:4' || workers != 0 || bind != '127.0.0.1'

          if config_file && has_options
            Onetime.app_logger.error('Cannot specify both a config file and command-line options')
            exit 1
          end

          app, = Rack::Builder.parse_file('config.ru')

          config = {
            app: app,
            environment: environment,
            Host: bind,
            Port: port,
          }

          case [config_file, server]
          when [String, _]
            config.merge!(config_files: config_file)

          when [nil, 'puma']
            thread_config = parse_threads(threads)
            config.merge!(
              Threads: "#{thread_config[:min]}:#{thread_config[:max]}",
              Workers: workers,
            )

          when [nil, 'thin']
            # Thin does not support threads or workers
          end

          # We remove app from the logged config to avoid cluttering the log
          loggable_config = config.reject { |k, _| k == :app }.inspect
          Onetime.app_logger.debug("Starting #{server} with config: #{loggable_config}")

          Rackup::Handler.get(server).run(config[:app], **config)
        end

        private

        def parse_threads(threads_str)
          min, max = threads_str.split(':').map(&:to_i)
          { min: min, max: max }
        end
      end

      # Register the command
      register 'server', ServerCommand
    end
  end
end
