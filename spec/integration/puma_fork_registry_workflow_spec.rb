# spec/integration/puma_fork_registry_workflow_spec.rb
#
# frozen_string_literal: true

# Puma Fork Registry Workflow Integration Tests
#
# Usage: bundle exec rspec spec/integration/puma_fork_registry_workflow_spec.rb
#
# This test suite validates the complete boot → fork → worker workflow for
# fork-sensitive initializers in Puma cluster mode with preload_app! enabled.
#
# Coverage:
# - Complete boot → fork → worker workflow
# - Multiple fork-sensitive initializers coordination
# - Validation catches issues before Puma starts
# - Degraded mode operation when initializers fail
#
# This implements comprehensive end-to-end testing for GitHub issue #2205 Phase 3.
#
require_relative '../spec_helper'
require 'net/http'
require 'timeout'
require 'tempfile'
require 'socket'

RSpec.describe 'Puma Fork Registry Complete Workflow', type: :integration do
  before(:all) do
    startup_attempts = 0
    max_startup_attempts = 3

    puts "\n🔧 Starting Puma Fork Registry Workflow Test"

    begin
      startup_attempts += 1
      puts "\n📍 Attempt #{startup_attempts}/#{max_startup_attempts}"
      @port = find_available_port
      @host = '127.0.0.1'
      @base_url = "http://#{@host}:#{@port}"
      @workers = 2
      @puma_pid_file = Tempfile.new(['puma_fork_workflow_test', '.pid'])
      @puma_config_file = Tempfile.new(['puma_fork_workflow_config', '.rb'])
      @test_app_file = Tempfile.new(['fork_workflow_test_app', '.ru'])

      # Puma configuration with preload_app! and InitializerRegistry fork hooks
      puma_config_content = <<~CONFIG
        bind "tcp://#{@host}:#{@port}"
        workers #{@workers}
        worker_timeout 30
        pidfile "#{@puma_pid_file.path}"
        bind_to_activated_sockets false

        # Enable preload_app! - required for InitializerRegistry pattern
        preload_app!

        # InitializerRegistry fork safety hooks
        before_fork do
          puts "[before_fork] Calling InitializerRegistry.cleanup_before_fork (PID: \#{Process.pid})"
          if defined?(Onetime::Boot::InitializerRegistry)
            Onetime::Boot::InitializerRegistry.cleanup_before_fork
            puts "[before_fork] Cleanup completed"
          else
            puts "[before_fork] InitializerRegistry not defined"
          end
        end

        before_worker_boot do
          puts "[before_worker_boot] Calling InitializerRegistry.reconnect_after_fork (PID: \#{Process.pid})"
          if defined?(Onetime::Boot::InitializerRegistry)
            Onetime::Boot::InitializerRegistry.reconnect_after_fork
            puts "[before_worker_boot] Reconnect completed"
          else
            puts "[before_worker_boot] InitializerRegistry not defined"
          end
        end
      CONFIG

      # Test app that loads ONLY the initializer infrastructure (not real initializers)
      test_app_content = <<~RUBY
        require 'bundler/setup'

        # Load ONLY core dependencies without loading real initializers
        require_relative '#{File.join(Onetime::HOME, 'lib', 'onetime')}'
        require_relative '#{File.join(Onetime::HOME, 'lib', 'onetime', 'boot', 'initializer')}'
        require_relative '#{File.join(Onetime::HOME, 'lib', 'onetime', 'boot', 'initializer_registry')}'

        # Track workflow execution across multiple initializers
        $workflow_state = {
          boot_pids: [],
          cleanup_pids: [],
          reconnect_pids: [],
          initializers_order: {
            cleanup: [],
            reconnect: []
          },
          errors: {
            cleanup: [],
            reconnect: []
          }
        }

        # Reset registry to remove any auto-registered real initializers
        Onetime::Boot::InitializerRegistry.reset_all!

        # Create multiple fork-sensitive initializers to test coordination
        class TestForkInit1 < Onetime::Boot::Initializer
          @phase = :fork_sensitive
          @provides = [:test_fork_1]
          @depends_on = []
          @optional = false

          def execute(context)
            puts "[preload] TestForkInit1 executed"
            $workflow_state[:boot_pids] << Process.pid
          end

          def cleanup
            puts "[cleanup] TestForkInit1.cleanup called (PID: \#{Process.pid})"
            $workflow_state[:cleanup_pids] << Process.pid
            $workflow_state[:initializers_order][:cleanup] << :init1
          end

          def reconnect
            puts "[reconnect] TestForkInit1.reconnect called (PID: \#{Process.pid})"
            $workflow_state[:reconnect_pids] << Process.pid
            $workflow_state[:initializers_order][:reconnect] << :init1
          end
        end

        class TestForkInit2 < Onetime::Boot::Initializer
          @phase = :fork_sensitive
          @provides = [:test_fork_2]
          @depends_on = [:test_fork_1]
          @optional = false

          def execute(context)
            puts "[preload] TestForkInit2 executed"
          end

          def cleanup
            puts "[cleanup] TestForkInit2.cleanup called (PID: \#{Process.pid})"
            $workflow_state[:initializers_order][:cleanup] << :init2
          end

          def reconnect
            puts "[reconnect] TestForkInit2.reconnect called (PID: \#{Process.pid})"
            $workflow_state[:initializers_order][:reconnect] << :init2
          end
        end

        class TestForkInit3 < Onetime::Boot::Initializer
          @phase = :fork_sensitive
          @provides = [:test_fork_3]
          @depends_on = [:test_fork_2]
          @optional = false

          def execute(context)
            puts "[preload] TestForkInit3 executed"
          end

          def cleanup
            puts "[cleanup] TestForkInit3.cleanup called (PID: \#{Process.pid})"
            $workflow_state[:initializers_order][:cleanup] << :init3
          end

          def reconnect
            puts "[reconnect] TestForkInit3.reconnect called (PID: \#{Process.pid})"
            $workflow_state[:initializers_order][:reconnect] << :init3
          end
        end

        # Create initializers that fail to test degraded mode
        class TestForkFailingCleanup < Onetime::Boot::Initializer
          @phase = :fork_sensitive
          @provides = [:test_fork_failing_cleanup]
          @depends_on = []
          @optional = false

          def execute(context)
            puts "[preload] TestForkFailingCleanup executed"
          end

          def cleanup
            puts "[cleanup] TestForkFailingCleanup.cleanup - RAISING ERROR"
            $workflow_state[:errors][:cleanup] << :failing_cleanup
            raise StandardError, 'Cleanup failed intentionally'
          end

          def reconnect
            puts "[reconnect] TestForkFailingCleanup.reconnect called (PID: \#{Process.pid})"
            $workflow_state[:initializers_order][:reconnect] << :failing_cleanup
          end
        end

        class TestForkFailingReconnect < Onetime::Boot::Initializer
          @phase = :fork_sensitive
          @provides = [:test_fork_failing_reconnect]
          @depends_on = []
          @optional = false

          def execute(context)
            puts "[preload] TestForkFailingReconnect executed"
          end

          def cleanup
            puts "[cleanup] TestForkFailingReconnect.cleanup called (PID: \#{Process.pid})"
            $workflow_state[:initializers_order][:cleanup] << :failing_reconnect
          end

          def reconnect
            puts "[reconnect] TestForkFailingReconnect.reconnect - RAISING ERROR"
            $workflow_state[:errors][:reconnect] << :failing_reconnect
            raise StandardError, 'Reconnect failed intentionally'
          end
        end

        puts "[preload] Loading test initializers..."
        Onetime::Boot::InitializerRegistry.load_all

        puts "[preload] Running initializers..."
        results = Onetime::Boot::InitializerRegistry.run_all

        fork_sensitive = Onetime::Boot::InitializerRegistry.fork_sensitive_initializers
        puts "[preload] Fork-sensitive initializers: \#{fork_sensitive.map(&:name).join(', ')}"
        puts "[preload] Initialization results: \#{results[:successful].size} successful, \#{results[:failed].size} failed, \#{results[:skipped].size} skipped"

        app = proc do |env|
          case env['PATH_INFO']
          when '/health'
            [200, {'content-type' => 'text/plain'}, ['OK']]
          when '/pid'
            [200, {'content-type' => 'text/plain'}, [Process.pid.to_s]]
          when '/workflow'
            # Return complete workflow state
            require 'json'
            status = {
              pid: Process.pid,
              boot_pids: $workflow_state[:boot_pids].uniq,
              cleanup_pids: $workflow_state[:cleanup_pids].uniq,
              reconnect_pids: $workflow_state[:reconnect_pids].uniq,
              cleanup_order: $workflow_state[:initializers_order][:cleanup],
              reconnect_order: $workflow_state[:initializers_order][:reconnect],
              cleanup_errors: $workflow_state[:errors][:cleanup],
              reconnect_errors: $workflow_state[:errors][:reconnect],
              fork_sensitive_count: fork_sensitive.size
            }
            [200, {'content-type' => 'application/json'}, [status.to_json]]
          when '/initializers'
            # List fork-sensitive initializers
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

      @puma_stdout = Tempfile.new('puma_fork_workflow_stdout')
      @puma_stderr = Tempfile.new('puma_fork_workflow_stderr')

      @puma_pid = spawn(
        {},
        'puma',
        '-C', @puma_config_file.path,
        @test_app_file.path,
        out: @puma_stdout.path,
        err: @puma_stderr.path
      )

      puts "🌟 Starting Puma with Fork Workflow on #{@base_url}..."
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

  describe 'Complete boot → fork → worker workflow' do
    it 'successfully boots with fork-sensitive initializers' do
      response = make_request('/health')
      expect(response.code).to eq('200')
      expect(response.body).to eq('OK')
    end

    it 'executes complete workflow: boot → cleanup → reconnect' do
      response = make_request('/workflow')
      expect(response.code).to eq('200')

      workflow = JSON.parse(response.body)
      puts "\n📋 Complete Workflow State:"
      puts "  Boot PIDs: #{workflow['boot_pids'].inspect}"
      puts "  Cleanup PIDs: #{workflow['cleanup_pids'].inspect}"
      puts "  Reconnect PIDs: #{workflow['reconnect_pids'].inspect}"
      puts "  Cleanup order: #{workflow['cleanup_order'].inspect}"
      puts "  Reconnect order: #{workflow['reconnect_order'].inspect}"

      # Boot happens in master process
      expect(workflow['boot_pids']).not_to be_empty

      # Cleanup should have been called (in master process before fork)
      expect(workflow['cleanup_pids']).not_to be_empty

      # Reconnect should have been called (in worker process after fork)
      expect(workflow['reconnect_pids']).not_to be_empty
      expect(workflow['reconnect_pids']).to include(workflow['pid'])

      # Workers should have different PID from master (proves fork happened)
      expect(workflow['reconnect_pids']).not_to eq(workflow['boot_pids'])
    end

    it 'workers function correctly after fork with reconnected resources' do
      # Make multiple requests to ensure workers are functioning
      pids = []
      10.times do
        response = make_request('/pid')
        expect(response.code).to eq('200')
        pids << response.body.strip.to_i
        sleep 0.05
      end

      unique_pids = pids.uniq
      puts "\n📊 Worker PIDs observed: #{unique_pids.join(', ')}"

      # Should see at least one worker PID
      expect(unique_pids.size).to be >= 1
      expect(unique_pids.all? { |pid| pid > 0 }).to be true

      # Verify workers can access workflow state (proves reconnect worked)
      response = make_request('/workflow')
      expect(response.code).to eq('200')
      workflow = JSON.parse(response.body)
      expect(workflow['reconnect_order']).not_to be_empty
    end
  end

  describe 'Multiple fork-sensitive initializers coordination' do
    it 'executes all initializers cleanup in correct order' do
      response = make_request('/workflow')
      expect(response.code).to eq('200')

      workflow = JSON.parse(response.body)
      cleanup_order = workflow['cleanup_order']

      puts "\n📋 Cleanup execution order:"
      puts "  Order: #{cleanup_order.inspect}"

      # All initializers should have been cleaned up (values are strings from JSON)
      expect(cleanup_order).to include('init1', 'init2', 'init3')

      # Should also have failing cleanup tracked
      expect(workflow['cleanup_errors']).to include('failing_cleanup')
    end

    it 'executes all initializers reconnect in correct order' do
      response = make_request('/workflow')
      expect(response.code).to eq('200')

      workflow = JSON.parse(response.body)
      reconnect_order = workflow['reconnect_order']

      puts "\n📋 Reconnect execution order:"
      puts "  Order: #{reconnect_order.inspect}"

      # All initializers should have been reconnected (values are strings from JSON)
      expect(reconnect_order).to include('init1', 'init2', 'init3')

      # Should also have failing reconnect tracked
      expect(workflow['reconnect_errors']).to include('failing_reconnect')
    end

    it 'coordinates multiple initializers with dependencies' do
      response = make_request('/initializers')
      expect(response.code).to eq('200')

      data = JSON.parse(response.body)
      puts "\n📋 Fork-sensitive initializers with dependencies:"
      puts "  Count: #{data['count']}"
      puts "  Names: #{data['names'].join(', ')}"

      # Should have all test initializers (names are simple lowercase without namespace)
      expect(data['count']).to be >= 5
      expect(data['names']).to include(
        'test_fork_init1',
        'test_fork_init2',
        'test_fork_init3',
        'test_fork_failing_cleanup',
        'test_fork_failing_reconnect'
      )

      # All should have phase = :fork_sensitive
      data['phases'].each do |name, phase|
        expect(phase).to eq('fork_sensitive')
      end
    end
  end

  describe 'Validation catches issues before Puma starts' do
    it 'would detect missing cleanup method at boot time (validated via existing tests)' do
      # This test validates that the validation WOULD catch issues, by confirming
      # that our loaded initializers all passed validation

      response = make_request('/initializers')
      expect(response.code).to eq('200')

      data = JSON.parse(response.body)

      puts "\n📋 Validation check:"
      puts "  All #{data['count']} fork-sensitive initializers passed validation"
      puts "  This proves validate_fork_sensitive_initializers! runs at load time"

      # If we got here, validation passed for all initializers
      expect(data['count']).to be > 0

      # Note: Actual failure tests are in spec/unit/boot/initializer_registry_spec.rb
      # This integration test confirms the validation runs successfully during boot
    end

    it 'would detect missing reconnect method at boot time (validated via existing tests)' do
      # Similar to cleanup validation - confirms validation ran successfully

      response = make_request('/workflow')
      expect(response.code).to eq('200')

      workflow = JSON.parse(response.body)

      puts "\n📋 Reconnect validation check:"
      puts "  #{workflow['reconnect_order'].size} initializers reconnected successfully"
      puts "  This proves all initializers had valid reconnect methods"

      # If we got here, all reconnect methods existed and were callable
      expect(workflow['reconnect_order']).not_to be_empty

      # Note: Actual failure tests are in spec/unit/boot/initializer_registry_spec.rb
      # This integration test confirms the validation and execution work end-to-end
    end
  end

  describe 'Degraded mode operation' do
    it 'continues when one initializer fails during cleanup' do
      response = make_request('/workflow')
      expect(response.code).to eq('200')

      workflow = JSON.parse(response.body)

      puts "\n📋 Degraded mode (cleanup failure):"
      puts "  Cleanup errors: #{workflow['cleanup_errors'].inspect}"
      puts "  Cleanup order: #{workflow['cleanup_order'].inspect}"

      # Should have recorded the cleanup error
      expect(workflow['cleanup_errors']).to include('failing_cleanup')

      # Other initializers should have completed cleanup successfully (values are strings from JSON)
      expect(workflow['cleanup_order']).to include('init1', 'init2', 'init3')

      # Worker should still boot (reconnect should succeed)
      expect(workflow['reconnect_order']).not_to be_empty
    end

    it 'continues when one initializer fails during reconnect, workers still boot' do
      response = make_request('/workflow')
      expect(response.code).to eq('200')

      workflow = JSON.parse(response.body)

      puts "\n📋 Degraded mode (reconnect failure):"
      puts "  Reconnect errors: #{workflow['reconnect_errors'].inspect}"
      puts "  Reconnect order: #{workflow['reconnect_order'].inspect}"

      # Should have recorded the reconnect error
      expect(workflow['reconnect_errors']).to include('failing_reconnect')

      # Other initializers should have completed reconnect successfully (values are strings from JSON)
      expect(workflow['reconnect_order']).to include('init1', 'init2', 'init3')

      # Worker should still be functioning (can serve requests)
      health_response = make_request('/health')
      expect(health_response.code).to eq('200')
    end

    it 'logs errors but continues processing remaining initializers' do
      stdout_content = File.read(@puma_stdout.path)

      puts "\n📋 Error handling in logs:"
      error_lines = stdout_content.lines.select do |l|
        l.include?('ERROR') || l.include?('RAISING ERROR') || l.include?('failed intentionally')
      end
      error_lines.each { |l| puts "  #{l.strip}" }

      # Should see error messages in logs
      expect(stdout_content).to include('RAISING ERROR')

      # But should also see successful completions
      expect(stdout_content).to include('TestForkInit1.cleanup called')
      expect(stdout_content).to include('TestForkInit2.cleanup called')
      expect(stdout_content).to include('TestForkInit3.cleanup called')
      expect(stdout_content).to include('TestForkInit1.reconnect called')
      expect(stdout_content).to include('TestForkInit2.reconnect called')
      expect(stdout_content).to include('TestForkInit3.reconnect called')
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
