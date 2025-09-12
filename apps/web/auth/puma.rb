# Puma configuration for external auth service

# Number of workers and threads
workers ENV.fetch('WEB_CONCURRENCY', 2)
threads_count = ENV.fetch('RAILS_MAX_THREADS', 5)
threads threads_count, threads_count

# Bind to port
port ENV.fetch('PORT', 9393)
bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 9393)}"

# Environment
environment ENV.fetch('RACK_ENV', 'development')

# Preload application for better performance
preload_app!

# Worker and thread management
worker_timeout 30
worker_boot_timeout 30
worker_shutdown_timeout 30

# Process management
pidfile 'tmp/pids/server.pid' if ENV['RACK_ENV'] == 'production'
state_path 'tmp/pids/puma.state' if ENV['RACK_ENV'] == 'production'

# Logging
if ENV['RACK_ENV'] == 'production'
  stdout_redirect 'log/puma_stdout.log', 'log/puma_stderr.log', true
  quiet false
else
  # Development: show all logs
  quiet false
end

# Memory and performance
#
# nakayoshi_fork - Memory optimization for forked worker processes
#
# Enables additional garbage collection and heap compaction before forking
# new worker processes. This improves Copy-on-Write efficiency by reducing
# memory fragmentation, resulting in lower overall memory usage across workers.
#
# Built into Puma 5+, replaces the standalone nakayoshi_fork gem from 2018.
# Note: If you have the old nakayoshi_fork gem as a dependency, consider
# removing it to avoid running GC multiple times unnecessarily.
#
nakayoshi_fork ENV['RACK_ENV'] == 'production'

# Health check endpoint (internal)
activate_control_app 'tcp://127.0.0.1:9394', { auth_token: ENV.fetch('PUMA_CONTROL_TOKEN', 'changeme') }

# Restart workers periodically to prevent memory leaks
if ENV['RACK_ENV'] == 'production'
  worker_timeout 60
  worker_boot_timeout 60

  # Restart workers after serving N requests (prevents memory leaks)
  if ENV['MAX_WORKER_REQUESTS']
    worker_max_requests ENV.fetch('MAX_WORKER_REQUESTS', 1000).to_i
  end
end

# Development-specific configuration
if ENV['RACK_ENV'] == 'development'
  plugin :tmp_restart
end
