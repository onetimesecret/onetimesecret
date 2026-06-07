# lib/onetime/initializers/setup_heap_dump_handler.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # SetupHeapDumpHandler initializer
    #
    # Installs a SIGUSR2 signal handler that writes an ObjectSpace heap dump
    # to disk on demand. This gives operators a way to capture a Ruby heap
    # snapshot from a running process without attaching GDB or restarting with
    # extra instrumentation, which makes diagnosing RSS growth vs. Ruby heap
    # growth in production containers significantly easier.
    #
    # Because this runs as a boot initializer, the handler is installed once for
    # every OTS process regardless of execution mode (:web, :scheduler, :worker,
    # :cli). In Puma/Sneakers cluster mode the handler is installed in the master
    # process and inherited by forked workers — this is why the initializer is
    # NOT marked @phase = :fork_sensitive. Marking it fork-sensitive would cause
    # cleanup_before_fork to tear it down before workers are spawned, leaving
    # them without the handler.
    #
    # Usage (after deploy):
    #   podman exec <container> kill -USR2 <pid>
    #   # then analyze the dump with: scripts/analyze-heapdump <file>
    #
    # The dump is written to HEAP_DUMP_DIR (default /tmp) as
    # heap-<pid>-<epoch>.json. Process.pid in the filename disambiguates master
    # vs. worker dumps in cluster mode.
    #
    # SECURITY: ObjectSpace.dump_all serializes the `value` of every live
    # String, so a heap dump captured while secrets are in memory contains
    # plaintext secrets, session tokens, and derived key material. The dump is
    # therefore written owner-only (0600) and created exclusively (O_EXCL) so it
    # cannot clobber or follow a pre-planted symlink in a shared /tmp. Treat the
    # resulting file as a credential: restrict, transfer securely, and delete it
    # once analysis is complete.
    #
    class SetupHeapDumpHandler < Onetime::Boot::Initializer
      @provides = [:heap_dump]
      # Failing to install a diagnostic signal handler (e.g. USR2 unavailable on
      # the platform) must never block application boot.
      @optional = true

      # Directory where heap dumps are written. Overridable so containers with a
      # locked-down /tmp can redirect dumps to a writable volume.
      DUMP_DIR = ENV.fetch('HEAP_DUMP_DIR', '/tmp')

      def execute(_context)
        Signal.trap('USR2') do
          # ObjectSpace.dump_all is not signal-safe; running it directly in the
          # trap context can deadlock or corrupt VM state. Spawning a thread
          # defers the work to a normal execution context.
          Thread.new do
            require 'objspace'
            path = File.join(DUMP_DIR, "heap-#{Process.pid}-#{Time.now.to_i}.json")
            # WRONLY|CREAT|EXCL + 0600: the dump contains plaintext secrets, so
            # create it owner-only and refuse to write through an existing file
            # or symlink (anti-clobber in a shared /tmp).
            File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |f|
              ObjectSpace.dump_all(output: f)
            end
            Onetime.boot_logger.info "[heap] Dump written to #{path}"
          rescue StandardError => ex
            Onetime.boot_logger.error "[heap] Dump failed: #{ex.class}: #{ex.message}"
          end
        end

        Onetime.boot_logger.debug "[init] SIGUSR2 heap dump handler installed (dir=#{DUMP_DIR})"
      end
    end
  end
end
