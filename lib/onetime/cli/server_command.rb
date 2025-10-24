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

module Onetime
  class ServerCommand < Onetime::CLI::DelayBoot
    def server
      # Get options with defaults
      server_type = option.server || 'puma'
      port        = option.port || 7143
      environment = option.environment || 'development'
      threads     = option.threads || '2:4'
      workers     = option.workers || 0
      bind_addr   = option.bind || '0.0.0.0'

      # Build the command based on server type
      cmd = case server_type.downcase
            when 'puma'
              "bundle exec puma -p #{port} -t #{threads} -w #{workers} -e #{environment}"
            when 'thin'
              # Thin uses different flags: -e for environment, -R for rackup, -a for address
              "bundle exec thin -e #{environment} -R config.ru -p #{port} -a #{bind_addr} start"
            else
              raise "Unknown server type: #{server_type}. Use 'puma' or 'thin'"
            end

      # Output to stderr so it's visible before server starts
      $stderr.puts
      $stderr.puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      $stderr.puts "Starting #{server_type.capitalize} Server"
      $stderr.puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      $stderr.puts
      $stderr.puts "Configuration:"
      $stderr.puts "  Server:      #{server_type}"
      $stderr.puts "  Port:        #{port}"
      $stderr.puts "  Environment: #{environment}"
      if server_type.downcase == 'puma'
        $stderr.puts "  Threads:     #{threads}"
        $stderr.puts "  Workers:     #{workers}"
      else
        $stderr.puts "  Bind:        #{bind_addr}"
      end
      $stderr.puts
      $stderr.puts "Executing:"
      $stderr.puts "  #{cmd}"
      $stderr.puts
      $stderr.puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      $stderr.puts

      # Execute server
      Kernel.exec(cmd)
    end
  end
end
