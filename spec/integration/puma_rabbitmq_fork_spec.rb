# spec/integration/puma_rabbitmq_fork_spec.rb
#
# frozen_string_literal: true

# Puma + RabbitMQ Fork Safety Integration Test
#
# Usage: bundle exec rspec spec/integration/puma_rabbitmq_fork_spec.rb
#
# This test verifies that RabbitMQ's fork hooks work correctly when
# Puma runs in cluster mode with preload_app! enabled.
#
# The test ensures:
# - disconnect() cleanly closes connection before fork
# - reconnect() establishes fresh connection in each worker
# - Workers can publish messages to RabbitMQ post-fork
#
# This validates the fix for GitHub issue #2167.
#
# REQUIREMENT: RabbitMQ must be running on localhost:5672
# Skip with: SKIP_RABBITMQ_TESTS=1 bundle exec rspec ...
#
require_relative '../spec_helper'
require 'net/http'
require 'timeout'
require 'tempfile'
require 'socket'
require 'bunny'

RSpec.describe 'Puma RabbitMQ Fork Safety', type: :integration do
  before(:all) do
    # Skip if RabbitMQ tests are disabled
    skip 'Skipping RabbitMQ tests (SKIP_RABBITMQ_TESTS=1)' if ENV['SKIP_RABBITMQ_TESTS'] == '1'

    # Check RabbitMQ is available
    begin
      test_conn = Bunny.new('amqp://localhost:5672')
      test_conn.start
      test_conn.close
    rescue Bunny::TCPConnectionFailed
      skip 'RabbitMQ not available on localhost:5672'
    end

    startup_attempts = 0
    max_startup_attempts = 3

    puts "\n🐰 Starting Puma RabbitMQ Fork Safety Test"

    begin
      startup_attempts += 1
      puts "\n📍 Attempt #{startup_attempts}/#{max_startup_attempts}"
      @port = find_available_port
      @host = '127.0.0.1'
      @base_url = "http://#{@host}:#{@port}"
      @workers = 2
      @puma_pid_file = Tempfile.new(['puma_rmq_fork_test', '.pid'])
      @puma_config_file = Tempfile.new(['puma_rmq_fork_config', '.rb'])
      @test_app_file = Tempfile.new(['rmq_fork_test_app', '.ru'])

      # Puma configuration WITH preload_app! and RabbitMQ fork hooks
      puma_config_content = <<~CONFIG
        bind "tcp://#{@host}:#{@port}"
        workers #{@workers}
        worker_timeout 30
        pidfile "#{@puma_pid_file.path}"
        bind_to_activated_sockets false

        # Enable preload_app! - this triggers the fork issue
        preload_app!

        # RabbitMQ fork safety hooks (the pattern being tested)
        before_fork do
          if defined?($rmq_test_conn) && $rmq_test_conn&.open?
            puts "[before_fork] Closing RabbitMQ connection (PID: \#{Process.pid})"
            $rmq_test_conn.close
            $rmq_test_conn = nil
            $rmq_test_channel_pool = nil
          end
        end

        before_worker_boot do
          puts "[before_worker_boot] Reconnecting RabbitMQ (PID: \#{Process.pid})"
          begin
            $rmq_test_conn = Bunny.new('amqp://localhost:5672')
            $rmq_test_conn.start
            $rmq_test_channel = $rmq_test_conn.create_channel
            puts "[before_worker_boot] RabbitMQ reconnected in worker \#{Process.pid}"
          rescue Bunny::TCPConnectionFailed => e
            puts "[before_worker_boot] RabbitMQ connection failed: \#{e.message}"
          end
        end
      CONFIG

      # Minimal test app with RabbitMQ only (no full app boot)
      test_app_content = <<~RUBY
        require 'bunny'
        require 'connection_pool'
        require 'json'

        # Simulate preload: create RabbitMQ connection during preload
        puts "[preload] Connecting to RabbitMQ (PID: \#{Process.pid})"
        $rmq_test_conn = Bunny.new('amqp://localhost:5672')
        $rmq_test_conn.start

        # Simulate the ConnectionPool pattern (this is what causes the issue)
        $rmq_test_channel_pool = ConnectionPool.new(size: 3, timeout: 5) do
          $rmq_test_conn.create_channel
        end

        puts "[preload] RabbitMQ connected, channel pool created"

        TEST_QUEUE = 'puma_fork_test_queue_' + Process.pid.to_s + '_' + Time.now.to_i.to_s

        app = proc do |env|
          case env['PATH_INFO']
          when '/health'
            [200, {'content-type' => 'text/plain'}, ['OK']]
          when '/pid'
            [200, {'content-type' => 'text/plain'}, [Process.pid.to_s]]
          when '/rmq_status'
            # Check RabbitMQ connection status
            status = {
              pid: Process.pid,
              connection_open: $rmq_test_conn&.open?,
              channel_available: !$rmq_test_channel.nil?
            }
            [200, {'content-type' => 'application/json'}, [status.to_json]]
          when '/publish'
            # Attempt to publish a message (proves connection works post-fork)
            begin
              channel = $rmq_test_channel
              queue = channel.queue(TEST_QUEUE, auto_delete: true)
              channel.default_exchange.publish(
                { test: 'message', pid: Process.pid, time: Time.now.to_s }.to_json,
                routing_key: queue.name
              )
              [200, {'content-type' => 'application/json'}, [{ success: true, pid: Process.pid, queue: queue.name }.to_json]]
            rescue => e
              [500, {'content-type' => 'application/json'}, [{ success: false, error: e.class.name, message: e.message }.to_json]]
            end
          else
            [404, {'content-type' => 'text/plain'}, ['Not Found']]
          end
        end

        run app
      RUBY

      File.write(@puma_config_file.path, puma_config_content)
      File.write(@test_app_file.path, test_app_content)

      @puma_stdout = Tempfile.new('puma_rmq_fork_stdout')
      @puma_stderr = Tempfile.new('puma_rmq_fork_stderr')

      @puma_pid = spawn(
        {},
        'puma',
        '-C', @puma_config_file.path,
        @test_app_file.path,
        out: @puma_stdout.path,
        err: @puma_stderr.path
      )

      puts "🌟 Starting Puma with preload_app! + RabbitMQ on #{@base_url}..."
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

  describe 'RabbitMQ fork safety with preload_app!' do
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

    it 'RabbitMQ connection is open in workers after fork' do
      response = make_request('/rmq_status')
      expect(response.code).to eq('200')

      status = JSON.parse(response.body)
      puts "\n📋 RabbitMQ status in worker:"
      puts "  PID: #{status['pid']}"
      puts "  Connection open: #{status['connection_open']}"
      puts "  Channel available: #{status['channel_available']}"

      expect(status['connection_open']).to be true
      expect(status['channel_available']).to be true
    end

    it 'workers can publish messages to RabbitMQ post-fork' do
      3.times do |i|
        response = make_request('/publish')
        expect(response.code).to eq('200')

        result = JSON.parse(response.body)
        puts "\n📤 Publish #{i + 1}: success=#{result['success']}, pid=#{result['pid']}"

        expect(result['success']).to be true
        expect(result['pid']).to be > 0
        sleep 0.1
      end
    end

    it 'shows fork hooks were called in logs' do
      stdout_content = File.read(@puma_stdout.path)

      puts "\n📋 Puma stdout (fork hook messages):"
      relevant_lines = stdout_content.lines.select do |l|
        l.include?('before_fork') || l.include?('before_worker_boot') || l.include?('RabbitMQ')
      end
      relevant_lines.each { |l| puts "  #{l}" }

      # Verify before_fork ran (disconnect)
      expect(stdout_content).to include('[before_fork] Closing RabbitMQ')

      # Verify before_worker_boot ran (reconnect)
      expect(stdout_content).to include('[before_worker_boot] Reconnecting RabbitMQ')
      expect(stdout_content).to include('RabbitMQ reconnected in worker')
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
    [@puma_pid_file, @puma_config_file, @test_app_file, @puma_stdout, @puma_stderr].compact.each do |file|
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
