# lib/onetime/cli/server_command.rb
#
# CLI command for running the web server (Puma or Thin)
#
# Usage:
#   ots server [options]
#
# Options:
#   -s, --server TYPE       Server type: puma or thin (default: puma)
#   -p, --port PORT         Port to bind to (default: 7143)
#   -e, --environment ENV   Environment to run in (default: development)
#   -t, --threads MIN:MAX   Thread pool size for Puma (default: 2:4)
#   -w, --workers COUNT     Number of workers for Puma (default: 0)
#   -b, --bind ADDRESS      Bind address for Thin (default: 0.0.0.0)
#

require 'rackup'

module Onetime
  class ServerCommand < Onetime::CLI::DelayBoot
    def server
      server_type = option.server || 'puma'
      port = option.port || 7143
      env = option.environment || 'development'

      app, _ = Rack::Builder.parse_file('config.ru')

      config = {
          app: app,
          Host: option.bind || '0.0.0.0',
          Port: port,
          environment: env
        }

        case server_type.downcase
        when 'puma'
          threads = parse_threads(option.threads || '2:4')
          config.merge!(
            Threads: "#{threads[:min]}:#{threads[:max]}",
            workers: option.workers || 0
          )
        end

        Rackup::Handler.get(server_type).run(config[:app], **config)
    end

    private

    def parse_threads(threads_str)
      min, max = threads_str.split(':').map(&:to_i)
      { min: min, max: max }
    end

    def log_startup(server, port, env)
      puts
      puts "→ #{server.capitalize} server"
      puts "  #{env} environment"
      puts "  http://#{option.bind || '0.0.0.0'}:#{port}"
      if server == 'puma'
        threads = parse_threads(option.threads || '2:4')
        puts "  #{threads[:min]}-#{threads[:max]} threads per worker"
        workers = option.workers || 0
        puts "  #{workers} #{'worker'.pluralize(workers)}" if workers > 0
      end
      puts
    end
  end
end
