# lib/onetime/cli/server_command.rb
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
  class ServerCommand < Onetime::CLI::DelayBoot
    def server
      config_file = argv.first
      has_options = option.port || option.threads || option.workers || option.bind

      if config_file && has_options
        Onetime.app_logger.error('Cannot specify both a config file and command-line options')
        exit 1
      end

      server_type = option.server || 'puma'
      port        = option.port || 7143
      env         = option.environment || 'development'

      app, = Rack::Builder.parse_file('config.ru')

      config = {
        app: app,
        environment: env,
        Host: option.bind || '127.0.0.1', # don't bind to all IP addresses by default
        Port: port,
      }

      case [config_file, server_type]

      in String, _
        config.merge!(config_files: config_file)

      in nil, 'puma'
        threads = parse_threads(option.threads || '2:4')
        config.merge!(
          Threads: "#{threads[:min]}:#{threads[:max]}",
          Workers: option.workers || 0,
        )

      in nil, 'thin'
        # Thin does not support threads or workers
      end

      # We remove app from the logged config to avoid cluttering the log
      loggable_config = config.reject { |k, _| k == :app }.inspect
      Onetime.app_logger.debug("Starting #{server_type} with config: #{loggable_config}")

      Rackup::Handler.get(server_type).run(config[:app], **config)
    end

    private

    def parse_threads(threads_str)
      min, max = threads_str.split(':').map(&:to_i)
      { min: min, max: max }
    end
  end
end
