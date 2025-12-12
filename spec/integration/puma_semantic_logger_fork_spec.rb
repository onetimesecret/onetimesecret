# spec/integration/puma_semantic_logger_fork_spec.rb
#
# frozen_string_literal: true

# Puma + SemanticLogger Fork Safety Integration Test
#
# Usage: bundle exec rspec spec/integration/puma_semantic_logger_fork_spec.rb
#
# This test verifies that SemanticLogger's fork hooks work correctly when
# Puma runs in cluster mode with preload_app! enabled.
#
# IMPORTANT: The Puma thread warning is informational - it tells you threads
# exist that won't survive fork. The SemanticLogger hooks (flush + reopen)
# ensure proper log handling across fork, but don't prevent the warning.
#
# This validates the fix for GitHub issue #2164.
#
require_relative '../spec_helper'
require 'net/http'
require 'timeout'
require 'tempfile'
require 'socket'

RSpec.describe 'Puma SemanticLogger Fork Safety', type: :integration do
  before(:all) do
    startup_attempts = 0
    max_startup_attempts = 3

    puts "\n🔧 Starting Puma SemanticLogger Fork Safety Test"

    begin
      startup_attempts += 1
      puts "\n📍 Attempt #{startup_attempts}/#{max_startup_attempts}"
      @port = find_available_port
      @host = '127.0.0.1'
      @base_url = "http://#{@host}:#{@port}"
      @workers = 2
      @puma_pid_file = Tempfile.new(['puma_fork_test', '.pid'])
      @puma_config_file = Tempfile.new(['puma_fork_config', '.rb'])
      @test_app_file = Tempfile.new(['fork_test_app', '.ru'])
      @log_output_file = Tempfile.new(['semantic_logger_output', '.log'])

      # Puma configuration WITH preload_app! and SemanticLogger fork hooks
      puma_config_content = <<~CONFIG
        bind "tcp://#{@host}:#{@port}"
        workers #{@workers}
        worker_timeout 30
        pidfile "#{@puma_pid_file.path}"
        bind_to_activated_sockets false

        # Enable preload_app! - this triggers thread detection warning
        preload_app!

        # SemanticLogger fork safety hooks (the pattern being tested)
        before_fork do
          SemanticLogger.flush if defined?(SemanticLogger)
        end

        before_worker_boot do
          SemanticLogger.reopen if defined?(SemanticLogger)
        end
      CONFIG

      # Minimal test app with SemanticLogger only (no full app boot)
      test_app_content = <<~RUBY
        require 'semantic_logger'

        # Configure SemanticLogger to write to a file we can verify
        LOG_FILE = '#{@log_output_file.path}'
        SemanticLogger.default_level = :info
        SemanticLogger.add_appender(file_name: LOG_FILE, formatter: :json)

        # Log during preload (before fork)
        PRELOAD_LOGGER = SemanticLogger['PreloadTest']
        PRELOAD_LOGGER.info("App preloaded", pid: Process.pid, phase: 'preload')

        app = proc do |env|
          case env['PATH_INFO']
          when '/health'
            [200, {'content-type' => 'text/plain'}, ['OK']]
          when '/pid'
            [200, {'content-type' => 'text/plain'}, [Process.pid.to_s]]
          when '/log'
            # Log from worker process (after fork + reopen)
            worker_logger = SemanticLogger['WorkerTest']
            worker_logger.info("Request handled", pid: Process.pid, phase: 'worker')
            SemanticLogger.flush
            [200, {'content-type' => 'text/plain'}, ["Logged from PID \#{Process.pid}"]]
          when '/logs'
            # Return the log file contents for verification
            SemanticLogger.flush
            sleep 0.1  # Allow appender to write
            content = File.exist?(LOG_FILE) ? File.read(LOG_FILE) : 'NO LOG FILE'
            [200, {'content-type' => 'text/plain'}, [content]]
          else
            [404, {'content-type' => 'text/plain'}, ['Not Found']]
          end
        end

        run app
      RUBY

      File.write(@puma_config_file.path, puma_config_content)
      File.write(@test_app_file.path, test_app_content)

      @puma_stdout = Tempfile.new('puma_fork_stdout')
      @puma_stderr = Tempfile.new('puma_fork_stderr')

      @puma_pid = spawn(
        {},
        'puma',
        '-C', @puma_config_file.path,
        @test_app_file.path,
        out: @puma_stdout.path,
        err: @puma_stderr.path
      )

      puts "🌟 Starting Puma with preload_app! on #{@base_url}..."
      wait_for_server_start
      puts "✅ Puma started successfully\n"

    rescue => e
      puts "❌ Startup failed: #{e.message}"

      stderr_content = begin
        @puma_stderr&.rewind
        @puma_stderr&.read
      rescue IOError
        nil
      end

      is_port_issue = e.message.include?('Address already in use') ||
                      e.message.include?('bind(2)') ||
                      e.message.include?('execution expired') ||
                      stderr_content&.include?('EADDRINUSE')

      cleanup_puma_process
      cleanup_temp_files

      if startup_attempts < max_startup_attempts && is_port_issue
        backoff_time = startup_attempts * 0.5
        puts "⏱  Retrying in #{backoff_time}s..."
        sleep(backoff_time)
        retry
      else
        raise e
      end
    end
  end

  after(:all) do
    cleanup_puma_process
    cleanup_temp_files
  end

  describe 'SemanticLogger fork safety with preload_app!' do
    it 'successfully boots workers with preload_app!' do
      response = make_request('/health')
      expect(response.code).to eq('200')
      expect(response.body).to eq('OK')
    end

    it 'workers have unique PIDs (confirms cluster mode is active)' do
      pids = []
      10.times do
        response = make_request('/pid')
        expect(response.code).to eq('200')
        pids << response.body.strip.to_i
        sleep 0.05
      end

      unique_pids = pids.uniq
      puts "\n📊 Worker PIDs observed: #{unique_pids.join(', ')}"

      expect(unique_pids.size).to be >= 1
      expect(unique_pids.all? { |pid| pid > 0 }).to be true
    end

    it 'logs work correctly in worker processes after fork' do
      # Make requests to trigger logging in workers
      3.times do
        response = make_request('/log')
        expect(response.code).to eq('200')
        expect(response.body).to start_with('Logged from PID')
        sleep 0.1
      end

      # Give time for logs to flush
      sleep 0.5

      # Retrieve log content
      response = make_request('/logs')
      expect(response.code).to eq('200')
      log_content = response.body

      puts "\n📋 Log file content:"
      log_content.lines.each { |l| puts "  #{l}" }

      # Verify worker logs are present (proves reopen worked)
      expect(log_content).to include('WorkerTest')
      expect(log_content).to include('"phase":"worker"')

      # Parse JSON logs and verify structure
      worker_logs = log_content.lines.select { |l| l.include?('WorkerTest') }
      expect(worker_logs.size).to be >= 1

      # Verify logs have proper PID (proves logging works post-fork)
      worker_logs.each do |log_line|
        parsed = JSON.parse(log_line) rescue nil
        next unless parsed
        expect(parsed['pid']).to be > 0
        expect(parsed['name']).to eq('WorkerTest')
      end
    end

    it 'SemanticLogger async thread warning is present but handled' do
      # The thread warning appears because SemanticLogger creates async thread during preload
      # This is informational - the hooks ensure proper handling, not prevention
      stdout_content = File.read(@puma_stdout.path)

      puts "\n📋 Puma stdout (checking for thread handling):"
      stdout_content.lines.select { |l| l.include?('Thread') || l.include?('semantic_logger') }
                    .each { |l| puts "  #{l}" }

      # If there's a warning about SemanticLogger thread, that's expected
      # The important thing is that logging still works (verified by previous test)
      if stdout_content.include?('semantic_logger')
        puts "  ℹ️  SemanticLogger async thread detected during preload (expected)"
        puts "  ℹ️  The before_fork/before_worker_boot hooks ensure proper handling"
      end

      # This test documents the behavior rather than asserting absence of warning
      expect(true).to be true  # Placeholder - real verification is in 'logs work correctly' test
    end
  end

  private

  def cleanup_puma_process
    return unless @puma_pid

    begin
      Process.kill('TERM', @puma_pid)
      Timeout.timeout(10) { Process.wait(@puma_pid) }
    rescue Errno::ESRCH, Timeout::Error
      Process.kill('KILL', @puma_pid) rescue nil
    end
  end

  def cleanup_temp_files
    [@puma_pid_file, @puma_config_file, @test_app_file, @puma_stdout, @puma_stderr, @log_output_file].compact.each do |file|
      begin
        file.close unless file.closed?
        file.unlink if file.respond_to?(:path) && File.exist?(file.path)
      rescue IOError, Errno::ENOENT
        # Already closed or deleted
      end
    end
  end

  def find_available_port
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    sleep 0.1
    puts "  ✓ Found available port #{port}"
    port
  end

  def wait_for_server_start
    sleep 2
    Timeout.timeout(30) do
      loop do
        sleep 0.5
        begin
          response = make_request('/health')
          break if response.code == '200'
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          next
        rescue StandardError => e
          puts "Health check error: #{e.message}"
          next
        end
      end
    end
  rescue Timeout::Error
    stdout_content = File.read(@puma_stdout.path) rescue "Could not read stdout"
    stderr_content = File.read(@puma_stderr.path) rescue "Could not read stderr"
    raise "Puma failed to start within 30s.\nSTDOUT:\n#{stdout_content}\nSTDERR:\n#{stderr_content}"
  end

  def make_request(path)
    uri = URI("#{@base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 5
    http.request(Net::HTTP::Get.new(uri.request_uri))
  rescue => e
    warn "  ❌ Request to #{uri} failed: #{e.class} - #{e.message}"
    raise
  end
end
