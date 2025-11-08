# etc/examples/puma.example.rb
#
# frozen_string_literal: true

#
# Puma configuration for Onetime Secret
# Copy to etc/puma.rb or config/puma.rb to customize
#
# USAGE:
#   Development: RACK_ENV=development bundle exec puma -C config/puma.rb
#   Production:  RACK_ENV=production bundle exec puma -C config/puma.rb
#
# ENVIRONMENT VARIABLES:
#   RACK_ENV           - Environment mode (default: production)
#   WEB_CONCURRENCY    - Number of worker processes (default: 2 in prod, 0 in dev)
#   MAX_THREADS        - Max threads per worker (default: 5)
#   PORT               - HTTP port to bind (default: 3000)
#   PUMA_CONTROL_TOKEN - Auth token for control app (production)
#   MAX_WORKER_REQUESTS - Restart workers after N requests (production)

_rack_env = ENV.fetch('RACK_ENV', 'production').downcase
_port = ENV.fetch('PORT', 3000)

# Worker count defaults: 2 for production (cluster mode), 0 for development (single-process)
_worker_count = ENV.fetch('WEB_CONCURRENCY') { _rack_env == 'production' ? 2 : 0 }.to_i
_threads_count_min = ENV.fetch('MIN_THREADS') { _rack_env == 'production' ? 1 : 0 }.to_i
_threads_count_max = ENV.fetch('MAX_THREADS', 5).to_i

threads _threads_count_min, _threads_count_max
bind "tcp://0.0.0.0:#{_port}"
environment _rack_env

if _worker_count.positive?
  # Connection management for preload_app! (required for Redis/DB)
  # NOTE: These blocks only run in cluster mode (workers > 0).
  # In development with workers=0, Puma runs in single-process mode.
  before_fork do
    # Close connections in master before forking
    # Familia.redis.quit if defined?(Familia)
    # Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
  end

  # On Puma 6, use the 'on_worker_boot' hook here instead. Head's
  # up it is deprecated in Puma 7 and will be removed in v8.
  before_worker_boot do
    # Reconnect in each worker (auto-reconnects for Familia)
    # DB.reconnect if defined?(DB)
  end
end

# Environment-specific configuration
case _rack_env
when 'production'
  # Cluster mode: multiple worker processes for production
  workers _worker_count
  preload_app!
  # nakayoshi_fork was removed in Puma 6.0 - use fork_worker instead if needed

  # pidfile 'tmp/pids/server.pid'
  # state_path 'tmp/pids/puma.state'
  # stdout_redirect 'log/puma_stdout.log', 'log/puma_stderr.log', true

  quiet true

  worker_timeout 60
  worker_boot_timeout 60
  worker_shutdown_timeout 30

  # Optional: restart workers after N requests (helps with memory leaks)
  # worker_max_requests ENV.fetch('MAX_WORKER_REQUESTS', 1000).to_i

when 'development'
  # Single-process mode by default (workers=0) for easier debugging
  # Set WEB_CONCURRENCY > 0 to test cluster mode in development
  workers _worker_count if _worker_count > 0
  preload_app! if _worker_count > 0

  plugin :tmp_restart
  quiet true

  worker_timeout 30
  worker_boot_timeout 30

else
  raise "Unknown RACK_ENV: #{_rack_env}"
end
