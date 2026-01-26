# etc/examples/puma.example.rb
#
# frozen_string_literal: true

# Puma configuration for Onetime Secret
# Copy to etc/puma.rb to customize (done automatically in Docker)
#
# USAGE:
#   Development: RACK_ENV=development bundle exec puma -C etc/puma.rb
#   Production:  RACK_ENV=production bundle exec puma -C etc/puma.rb
#
# ENVIRONMENT VARIABLES:
#   RACK_ENV             - Environment mode (default: production)
#   PORT                 - HTTP port to bind (default: 3000)
#   PUMA_WORKERS         - Number of worker processes (default: 2 in prod, 0 in dev)
#   PUMA_MIN_THREADS     - Min threads per worker (default: 1 in prod, 0 in dev)
#   PUMA_MAX_THREADS     - Max threads per worker (default: 16)
#   WEB_CONCURRENCY      - Alias for PUMA_WORKERS (for compatibility)
#   MIN_THREADS          - Alias for PUMA_MIN_THREADS (for compatibility)
#   MAX_THREADS          - Alias for PUMA_MAX_THREADS (for compatibility)
#   PUMA_CONTROL_TOKEN   - Auth token for control app (production)
#   MAX_WORKER_REQUESTS  - Restart workers after N requests (production)

rack_env = ENV.fetch('RACK_ENV', 'production').downcase
port     = ENV.fetch('PORT', 3000)

# Worker count defaults: 2 for production (cluster mode), 0 for development (single-process)
# PUMA_WORKERS takes precedence over WEB_CONCURRENCY for Docker compatibility
default_workers   = rack_env == 'production' ? 2 : 0
worker_count      = ENV.fetch('PUMA_WORKERS') { ENV.fetch('WEB_CONCURRENCY', default_workers) }.to_i

# Thread settings: PUMA_*_THREADS take precedence over MIN_THREADS/MAX_THREADS
default_min       = rack_env == 'production' ? 1 : 0
threads_count_min = ENV.fetch('PUMA_MIN_THREADS') { ENV.fetch('MIN_THREADS', default_min) }.to_i
threads_count_max = ENV.fetch('PUMA_MAX_THREADS') { ENV.fetch('MAX_THREADS', 16) }.to_i

threads threads_count_min, threads_count_max
bind "tcp://0.0.0.0:#{port}"
environment rack_env

if worker_count.positive?
  # Connection management for preload_app! (required for fork-sensitive resources)
  # NOTE: These blocks only run in cluster mode (workers > 0).
  # In development with workers=0, Puma runs in single-process mode.
  before_fork do
    # Cleanup all fork-sensitive initializers (SemanticLogger, RabbitMQ, etc.)
    # Each initializer marked with @phase = :fork_sensitive implements cleanup method.
    # See: lib/onetime/boot/initializer_registry.rb
    Onetime.boot_registry&.cleanup_before_fork

    # Close connections in master before forking
    # Familia.dclient.quit if defined?(Familia)
    # Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
  end

  # On Puma 6, use the 'on_worker_boot' hook here instead. Head's
  # up it is deprecated in Puma 7 and will be removed in v8.
  before_worker_boot do
    # Reconnect all fork-sensitive initializers (SemanticLogger, RabbitMQ, etc.)
    # Each initializer marked with @phase = :fork_sensitive implements reconnect method.
    # See: lib/onetime/boot/initializer_registry.rb
    Onetime.boot_registry&.reconnect_after_fork

    # Reconnect in each worker (auto-reconnects for Familia)
    # DB.reconnect if defined?(DB)
  end
end

# Environment-specific configuration
case rack_env
when 'production'
  # Cluster mode: multiple worker processes for production
  workers worker_count
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
  workers worker_count if worker_count > 0
  preload_app! if worker_count > 0

  plugin :tmp_restart
  quiet true

  worker_timeout 30
  worker_boot_timeout 30

else
  raise "Unknown RACK_ENV: #{rack_env}"
end
