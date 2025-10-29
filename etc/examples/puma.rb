# etc/examples/puma.rb

# Example Puma configuration
#
# # config/puma.rb or inline configuration
#
# # Load the app before forking workers (copy-on-write optimization)
# preload_app!
#
# # Runs once in master process before forking
# before_fork do
#   # Close database connections, etc.
#   # ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
# end
#
# # Runs in each worker after fork
# on_worker_boot do
#   # Re-establish connections per worker
#   # ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
# end
#
# # Optional: runs in each worker on shutdown
# on_worker_shutdown do
#   # Cleanup
# end

is_production = ENV['RACK_ENV'] == 'production'
is_development = ENV['RACK_ENV'] == 'development'

# Number of workers and threads
workers ENV.fetch('WEB_CONCURRENCY', 2)
threads_count = ENV.fetch('MAX_THREADS', 5)
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

# Health check endpoint (internal)
# activate_control_app 'tcp://127.0.0.1:9394', { auth_token: ENV.fetch('PUMA_CONTROL_TOKEN', 'changeme') }

if is_production
  # === PRODUCTION SETTINGS ===

  # Process management
  pidfile 'tmp/pids/server.pid'
  state_path 'tmp/pids/puma.state'

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
  nakayoshi_fork true

  stdout_redirect 'log/puma_stdout.log', 'log/puma_stderr.log', true
  quiet true

  # Restart workers periodically to prevent memory leaks
  worker_timeout 60
  worker_boot_timeout 60

  # Restart workers after serving N requests (prevents memory leaks)
  if ENV['MAX_WORKER_REQUESTS']
    worker_max_requests ENV.fetch('MAX_WORKER_REQUESTS', 1000).to_i
  end
end

if is_development
  # === DEVELOPMENT SETTINGS ===

  plugin :tmp_restart

  # Silence all logs?
  quiet false
end


__END__

# Without a `puma.rb` file and without `preload_app!`:
#
# **With `workers: 0` (your current default):**
# - Puma runs in "single mode" - one process, multiple threads
# - App loads **once** in that single process before threads start
# - No forking happens - the "single mode" message you're seeing confirms this
# - All threads share the same memory space
#
# **With `workers: > 0` and no `preload_app!`:**
# - Master process starts but **doesn't load the app**
# - Each worker process loads the app **independently** from scratch
# - No copy-on-write optimization - full memory duplication per worker
# - Your initialization code runs `N` times (once per worker)
# - More memory usage, slower startup
#
# So the key difference: `preload_app!` determines **when** and **how many times** your app initializes in multi-worker mode. Without it, you lose the "initialize once, fork many" benefit.
#
# In your current setup with `workers: 0`, you're already getting single initialization - the app loads once in the main process. The threads spawn from there, sharing that loaded state. You only need `preload_app!` if you # switch to `workers > 0` and want initialization to happen once in the master before forking.
