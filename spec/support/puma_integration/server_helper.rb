# spec/support/puma_integration/server_helper.rb
#
# frozen_string_literal: true

# Helper module for managing Puma server lifecycle in integration tests.
# Handles port allocation, startup with retry, and graceful shutdown.
#
# Usage:
#   RSpec.describe 'My Puma Test' do
#     include PumaIntegration::ServerHelper
#
#     before(:all) { start_puma_with_retry }
#     after(:all) { shutdown_puma_server; cleanup_temp_files }
#   end

require 'net/http'
require 'timeout'
require 'tempfile'
require 'socket'

module PumaIntegration
  module ServerHelper
    MAX_STARTUP_ATTEMPTS = 3
    INITIAL_BACKOFF_SECONDS = 0.5
    STARTUP_TIMEOUT_SECONDS = 30
    SHUTDOWN_TIMEOUT_SECONDS = 10

    # Start Puma with automatic port finding and retry on conflicts.
    # Sets @port, @host, @base_url, @puma_pid, @puma_stdout, @puma_stderr
    def start_puma_with_retry
      attempt = 0

      begin
        attempt += 1
        puts "\n📍 Startup attempt #{attempt}/#{MAX_STARTUP_ATTEMPTS}"

        @port = find_available_port
        @host = '127.0.0.1'
        @base_url = "http://#{@host}:#{@port}"

        create_puma_temp_files
        spawn_puma_server
        wait_for_health_check

        puts "✅ Puma started on #{@base_url}\n"

      rescue StandardError => e
        puts "❌ Startup failed: #{e.message}"

        if attempt < MAX_STARTUP_ATTEMPTS && port_related_error?(e)
          cleanup_failed_attempt
          sleep(attempt * INITIAL_BACKOFF_SECONDS)
          retry
        else
          cleanup_failed_attempt
          raise
        end
      end
    end

    def shutdown_puma_server
      return unless @puma_pid

      begin
        Process.kill('TERM', @puma_pid)
        Timeout.timeout(SHUTDOWN_TIMEOUT_SECONDS) { Process.wait(@puma_pid) }
      rescue Errno::ESRCH
        # Process already gone
      rescue Timeout::Error
        Process.kill('KILL', @puma_pid) rescue nil
      end
    rescue StandardError => e
      warn "Warning: Error during Puma shutdown: #{e.message}"
    end

    def cleanup_temp_files
      [@puma_pid_file, @puma_config_file, @test_app_file, @puma_stdout, @puma_stderr].compact.each do |file|
        file.close unless file.closed?
        file.unlink if file.respond_to?(:path) && File.exist?(file.path)
      rescue IOError, Errno::ENOENT
        # Already closed or deleted
      end
    end

    def make_request(path)
      uri = URI("#{@base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 5
      http.request(Net::HTTP::Get.new(uri.request_uri))
    rescue StandardError => e
      warn "  ❌ Request to #{uri} failed: #{e.class} - #{e.message}"
      raise
    end

    private

    def find_available_port
      server = TCPServer.new('127.0.0.1', 0)
      port = server.addr[1]
      server.close
      sleep 0.1 # Allow OS to release port
      puts "  ✓ Found available port #{port}"
      port
    end

    def create_puma_temp_files
      @puma_pid_file = Tempfile.new(['puma_test', '.pid'])
      @puma_config_file = Tempfile.new(['puma_config', '.rb'])
      @test_app_file = Tempfile.new(['test_app', '.ru'])
      @puma_stdout = Tempfile.new('puma_stdout')
      @puma_stderr = Tempfile.new('puma_stderr')

      File.write(@puma_config_file.path, puma_config_content)
      File.write(@test_app_file.path, test_app_content)
    end

    def spawn_puma_server
      @puma_pid = spawn(
        {},
        'puma',
        '-C', @puma_config_file.path,
        @test_app_file.path,
        out: @puma_stdout.path,
        err: @puma_stderr.path
      )
      puts "🌟 Starting Puma on #{@base_url}..."
    end

    def wait_for_health_check
      sleep 2 # Initial grace period

      Timeout.timeout(STARTUP_TIMEOUT_SECONDS) do
        loop do
          sleep 0.5
          response = make_request('/health')
          return if response.code == '200'
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          # Not ready yet
        end
      end
    rescue Timeout::Error
      stdout = File.read(@puma_stdout.path) rescue "Could not read"
      stderr = File.read(@puma_stderr.path) rescue "Could not read"
      raise "Puma failed to start within #{STARTUP_TIMEOUT_SECONDS}s.\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
    end

    def port_related_error?(error)
      stderr_content = begin
        @puma_stderr&.rewind
        @puma_stderr&.read
      rescue IOError
        nil
      end

      error.message.include?('Address already in use') ||
        error.message.include?('bind(2)') ||
        error.message.include?('execution expired') ||
        stderr_content&.include?('EADDRINUSE')
    end

    def cleanup_failed_attempt
      shutdown_puma_server
      cleanup_temp_files
    end

    # Override these in your spec to customize Puma/app configuration
    def puma_workers
      2
    end

    # Puma configuration with InitializerRegistry fork hooks
    def puma_config_content
      <<~CONFIG
        bind "tcp://#{@host}:#{@port}"
        workers #{puma_workers}
        worker_timeout 30
        pidfile "#{@puma_pid_file.path}"
        bind_to_activated_sockets false

        preload_app!

        before_fork do
          puts "[before_fork] Calling InitializerRegistry.cleanup_before_fork (PID: \#{Process.pid})"
          if defined?(Onetime::Boot::InitializerRegistry)
            Onetime::Boot::InitializerRegistry.current.cleanup_before_fork
            puts "[before_fork] Cleanup completed"
          end
        end

        before_worker_boot do
          puts "[before_worker_boot] Calling InitializerRegistry.reconnect_after_fork (PID: \#{Process.pid})"
          if defined?(Onetime::Boot::InitializerRegistry)
            Onetime::Boot::InitializerRegistry.current.reconnect_after_fork
            puts "[before_worker_boot] Reconnect completed"
          end
        end
      CONFIG
    end

    # Rack application content - override in spec for custom behavior
    def test_app_content
      raise NotImplementedError, "Subclass must implement #test_app_content"
    end
  end
end
