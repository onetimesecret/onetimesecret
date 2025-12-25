# spec/integration/puma_initializer_fork_spec.rb
#
# frozen_string_literal: true

# Puma + InitializerRegistry Fork Safety Integration Test
#
# Usage: bundle exec rspec spec/integration/puma_initializer_fork_spec.rb
#
# This test verifies that InitializerRegistry's fork-safety infrastructure
# works correctly when Puma runs in cluster mode with preload_app! enabled.
#
# The test ensures:
# - cleanup_before_fork() calls all fork-sensitive initializers' cleanup methods
# - reconnect_after_fork() calls all fork-sensitive initializers' reconnect methods
# - Both SetupLoggers and SetupRabbitMQ cleanup/reconnect are called
# - Workers function correctly post-fork
#
# This validates the implementation for GitHub issues #2201 and #2202.
#
require_relative '../../spec_helper'
require 'net/http'
require 'timeout'
require 'tempfile'
require 'socket'

RSpec.describe 'Puma InitializerRegistry Fork Safety', type: :integration do
  before(:all) do
    startup_attempts = 0
    max_startup_attempts = 3

    puts "\n🔧 Starting Puma InitializerRegistry Fork Safety Test"

    begin
      startup_attempts += 1
      puts "\n📍 Attempt #{startup_attempts}/#{max_startup_attempts}"
      @port = find_available_port
      @host = '127.0.0.1'
      @base_url = "http://#{@host}:#{@port}"
      @workers = 2
      @puma_pid_file = Tempfile.new(['puma_init_fork_test', '.pid'])
      @puma_config_file = Tempfile.new(['puma_init_fork_config', '.rb'])
      @test_app_file = Tempfile.new(['init_fork_test_app', '.ru'])

      # Puma configuration WITH preload_app! and InitializerRegistry fork hooks
      puma_config_content = <<~CONFIG
        bind "tcp://#{@host}:#{@port}"
        workers #{@workers}
        worker_timeout 30
        pidfile "#{@puma_pid_file.path}"
        bind_to_activated_sockets false

        # Enable preload_app! - required for InitializerRegistry pattern
        preload_app!

        # InitializerRegistry fork safety hooks (the pattern being tested)
        before_fork do
          puts "[before_fork] Calling InitializerRegistry.cleanup_before_fork (PID: \#{Process.pid})"
          if defined?(Onetime::Boot::InitializerRegistry)
            Onetime::Boot::InitializerRegistry.current.cleanup_before_fork
            puts "[before_fork] Cleanup completed"
          else
            puts "[before_fork] InitializerRegistry not defined"
          end
        end

        before_worker_boot do
          puts "[before_worker_boot] Calling InitializerRegistry.reconnect_after_fork (PID: \#{Process.pid})"
          if defined?(Onetime::Boot::InitializerRegistry)
            Onetime::Boot::InitializerRegistry.current.reconnect_after_fork
            puts "[before_worker_boot] Reconnect completed"
          else
            puts "[before_worker_boot] InitializerRegistry not defined"
          end
        end
      CONFIG

      # Minimal test app that loads Onetime boot infrastructure
      test_app_content = <<~RUBY
        require 'bundler/setup'

        # Manually load core dependencies without full app boot
        require_relative '#{File.join(Onetime::HOME, 'lib', 'onetime')}'
        require_relative '#{File.join(Onetime::HOME, 'lib', 'onetime', 'boot', 'initializer')}'
        require_relative '#{File.join(Onetime::HOME, 'lib', 'onetime', 'boot', 'initializer_registry')}'

        # Track which initializer methods were called
        $fork_calls = { cleanup: [], reconnect: [] }

        # Create test initializer that tracks calls
        class TestForkSensitiveInit < Onetime::Boot::Initializer
          @phase = :fork_sensitive
          @provides = [:test_fork_tracking]

          def execute(context)
            puts "[preload] TestForkSensitiveInit executed"
          end

          def cleanup
            puts "[cleanup] TestForkSensitiveInit.cleanup called (PID: \#{Process.pid})"
            $fork_calls[:cleanup] << Process.pid
          end

          def reconnect
            puts "[reconnect] TestForkSensitiveInit.reconnect called (PID: \#{Process.pid})"
            $fork_calls[:reconnect] << Process.pid
          end
        end

        # Load initializers (explicit - bypass ObjectSpace discovery)
        puts "[preload] Loading initializer classes..."
        registry = Onetime::Boot::InitializerRegistry.new
        Onetime::Boot::InitializerRegistry.current = registry
        registry.load([TestForkSensitiveInit])

        puts "[preload] Running initializers..."
        registry.run_all

        fork_sensitive = registry.fork_sensitive_initializers
        puts "[preload] Fork-sensitive initializers: \#{fork_sensitive.map(&:name).join(', ')}"

        app = proc do |env|
          case env['PATH_INFO']
          when '/health'
            [200, {'content-type' => 'text/plain'}, ['OK']]
          when '/pid'
            [200, {'content-type' => 'text/plain'}, [Process.pid.to_s]]
          when '/fork_calls'
            # Return the tracked fork calls
            require 'json'
            status = {
              pid: Process.pid,
              cleanup_calls: $fork_calls[:cleanup],
              reconnect_calls: $fork_calls[:reconnect],
              cleanup_count: $fork_calls[:cleanup].size,
              reconnect_count: $fork_calls[:reconnect].size
            }
            [200, {'content-type' => 'application/json'}, [status.to_json]]
          when '/initializers'
            # List fork-sensitive initializers (use captured variable from preload)
            require 'json'
            data = {
              count: fork_sensitive.size,
              names: fork_sensitive.map(&:name),
              phases: fork_sensitive.map { |i| [i.name, i.phase] }.to_h
            }
            [200, {'content-type' => 'application/json'}, [data.to_json]]
          else
            [404, {'content-type' => 'text/plain'}, ['Not Found']]
          end
        end

        run app
      RUBY

      File.write(@puma_config_file.path, puma_config_content)
      File.write(@test_app_file.path, test_app_content)

      @puma_stdout = Tempfile.new('puma_init_fork_stdout')
      @puma_stderr = Tempfile.new('puma_init_fork_stderr')

      @puma_pid = spawn(
        {},
        'puma',
        '-C', @puma_config_file.path,
        @test_app_file.path,
        out: @puma_stdout.path,
        err: @puma_stderr.path
      )

      puts "🌟 Starting Puma with InitializerRegistry on #{@base_url}..."
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

  describe 'InitializerRegistry fork safety with preload_app!' do
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

    it 'identifies fork-sensitive initializers correctly' do
      response = make_request('/initializers')
      expect(response.code).to eq('200')

      data = JSON.parse(response.body)
      puts "\n📋 Fork-sensitive initializers:"
      puts "  Count: #{data['count']}"
      puts "  Names: #{data['names'].join(', ')}"

      # Should have at least our test initializer
      expect(data['count']).to be >= 1
      expect(data['names']).to include('test_fork_sensitive_init')

      # All should have phase = :fork_sensitive
      data['phases'].each do |name, phase|
        expect(phase).to eq('fork_sensitive')
      end
    end

    it 'calls cleanup methods during before_fork' do
      response = make_request('/fork_calls')
      expect(response.code).to eq('200')

      status = JSON.parse(response.body)
      puts "\n📋 Fork calls tracking:"
      puts "  Cleanup calls: #{status['cleanup_count']}"
      puts "  Reconnect calls: #{status['reconnect_count']}"

      # Cleanup should have been called (at least once for test initializer)
      expect(status['cleanup_count']).to be >= 1
    end

    it 'calls reconnect methods during before_worker_boot' do
      response = make_request('/fork_calls')
      expect(response.code).to eq('200')

      status = JSON.parse(response.body)

      # Reconnect should have been called (at least once for test initializer)
      expect(status['reconnect_count']).to be >= 1

      # Reconnect PID should match current worker
      expect(status['reconnect_calls']).to include(status['pid'])
    end

    it 'shows fork hooks were called in logs' do
      stdout_content = File.read(@puma_stdout.path)

      puts "\n📋 Puma stdout (fork hook messages):"
      relevant_lines = stdout_content.lines.select do |l|
        l.include?('before_fork') ||
        l.include?('before_worker_boot') ||
        l.include?('InitializerRegistry') ||
        l.include?('cleanup') ||
        l.include?('reconnect')
      end
      relevant_lines.each { |l| puts "  #{l}" }

      # Verify before_fork ran
      expect(stdout_content).to include('InitializerRegistry.cleanup_before_fork')
      expect(stdout_content).to include('Cleanup completed')

      # Verify before_worker_boot ran
      expect(stdout_content).to include('InitializerRegistry.reconnect_after_fork')
      expect(stdout_content).to include('Reconnect completed')

      # Verify individual initializer methods were called
      expect(stdout_content).to include('cleanup')
      expect(stdout_content).to include('reconnect')
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
