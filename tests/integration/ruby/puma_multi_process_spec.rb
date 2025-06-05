# tests/integration/cli/puma_test.rb
#
# Puma Multi-Process Integration Test
#
# This test verifies that Puma's multi-process architecture correctly generates
# unique OT.instance values across worker processes. Since RSpec runs in a single
# process, we cannot directly test multi-process behavior through standard unit tests.
# This integration test launches an actual Puma server with multiple workers and
# validates the cross-process behavior.
#
# Purpose:
# 1. Verify OT.instance uniqueness across Puma worker processes
# 2. Ensure process-level identification works correctly in production-like environment
# 3. Validate that shared state (like @instance) behaves correctly across workers
# 4. Provide a testing platform for other multi-process concerns (database connections, caching, etc.)
#
# Test Strategy:
# - Launch Puma server with multiple workers (processes)
# - Create test endpoint that exposes OT.instance
# - Make multiple requests to collect instance values from different workers
# - Verify uniqueness and expected format
#
# This pattern can be extended to test other multi-process behaviors like:
# - Database connection pooling across workers
# - Redis connection behavior
# - Shared cache invalidation
# - Process-specific configuration
#
require_relative 'spec_helper'
require 'net/http'
require 'timeout'
require 'tempfile'

RSpec.describe 'Puma Multi-Process Integration', type: :integration do
  # Skip this test unless explicitly requested via environment variable
  # These tests are slow and require network resources
  before(:all) do
    skip 'Set PUMA_INTEGRATION_TESTS=1 to run' unless ENV['PUMA_INTEGRATION_TESTS']
  end

  let(:port) { 9292 }
  let(:host) { '127.0.0.1' }
  let(:base_url) { "http://#{host}:#{port}" }
  let(:workers) { 3 } # Number of Puma worker processes
  let(:puma_pid_file) { Tempfile.new(['puma_test', '.pid']) }
  let(:puma_config_file) { Tempfile.new(['puma_config', '.rb']) }

  # Puma configuration for multi-process testing
  let(:puma_config) do
    <<~CONFIG
      # Puma configuration for integration testing
      port #{port}
      bind "tcp://#{host}:#{port}"

      # Multi-process configuration
      workers #{workers}
      worker_timeout 30

      # Process management
      pidfile "#{puma_pid_file.path}"

      # Preload application for consistent initialization
      preload_app!

      # Logging for debugging
      stdout_redirect '/dev/null', '/dev/null', true

      # Graceful shutdown
      on_worker_boot do
        # Ensure each worker has its own database connections
        # This is where you'd reinitialize per-worker resources
      end
    CONFIG
  end

  # Minimal Rack application that exposes OT.instance for testing
  let(:test_app_file) { Tempfile.new(['test_app', '.ru']) }
  let(:test_app_content) do
    <<~RUBY
      # Test Rack application for Puma integration testing
      require_relative '#{File.expand_path('../../../lib/onetime', __FILE__)}'

      # Boot the application (this sets OT.instance)
      Onetime.boot! :test, false # Don't connect to DB for this test

      # Simple Rack app that returns OT.instance and process info
      app = proc do |env|
        case env['PATH_INFO']
        when '/instance'
          # Return OT.instance for verification
          [200, {'Content-Type' => 'text/plain'}, [Onetime.instance.to_s]]
        when '/pid'
          # Return process PID for verification
          [200, {'Content-Type' => 'text/plain'}, [Process.pid.to_s]]
        when '/health'
          # Health check endpoint
          [200, {'Content-Type' => 'text/plain'}, ['OK']]
        else
          [404, {'Content-Type' => 'text/plain'}, ['Not Found']]
        end
      end

      run app
    RUBY
  end

  before(:all) do
    # Write configuration files
    File.write(puma_config_file.path, puma_config)
    File.write(test_app_file.path, test_app_content)

    # Start Puma server in background
    @puma_pid = spawn(
      'puma',
      '-C', puma_config_file.path,
      test_app_file.path,
      out: '/dev/null',
      err: '/dev/null'
    )

    # Wait for server to start
    wait_for_server_start
  end

  after(:all) do
    # Clean shutdown
    if @puma_pid
      begin
        Process.kill('TERM', @puma_pid)
        Timeout.timeout(10) { Process.wait(@puma_pid) }
      rescue Errno::ESRCH, Timeout::Error
        # Process already gone or didn't shut down gracefully
        Process.kill('KILL', @puma_pid) rescue nil
      end
    end

    # Clean up temp files
    [puma_pid_file, puma_config_file, test_app_file].each(&:close!)
  end

  describe 'OT.instance across Puma workers' do
    it 'generates unique instance values for each worker process' do
      # Collect instance values from multiple requests
      # Each request may hit a different worker process
      instance_values = collect_instance_values(requests: 20)

      # Verify we got responses from multiple workers
      expect(instance_values.size).to be > 1,
        "Expected multiple unique instance values, got: #{instance_values}"

      # Verify each instance value has expected format
      instance_values.each do |instance_value|
        expect(instance_value).to match(/\A[a-f0-9]{40}\z/),
          "Instance value should be 40-character hex string: #{instance_value}"
      end
    end

    it 'correlates instance values with process IDs' do
      # Collect both instance values and PIDs
      correlations = collect_instance_pid_correlations(requests: 15)

      # Verify we have multiple worker processes
      unique_pids = correlations.map { |c| c[:pid] }.uniq
      expect(unique_pids.size).to be > 1,
        "Expected multiple worker PIDs, got: #{unique_pids}"

      # Verify consistent mapping: same PID = same instance
      correlations.group_by { |c| c[:pid] }.each do |pid, group|
        instance_values = group.map { |c| c[:instance] }.uniq
        expect(instance_values.size).to eq(1),
          "PID #{pid} should have consistent instance value, got: #{instance_values}"
      end
    end

    it 'maintains instance stability within worker lifecycle' do
      # Make multiple requests to same worker (via session affinity simulation)
      # In real scenarios, you might use sticky sessions or other routing
      pid_to_instances = {}

      10.times do
        response = make_request('/instance')
        pid_response = make_request('/pid')

        pid = pid_response.body.strip
        instance = response.body.strip

        pid_to_instances[pid] ||= []
        pid_to_instances[pid] << instance
      end

      # Verify each worker maintains same instance value
      pid_to_instances.each do |pid, instances|
        expect(instances.uniq.size).to eq(1),
          "Worker #{pid} should maintain consistent instance value"
      end
    end
  end

  private

  def wait_for_server_start
    Timeout.timeout(30) do
      loop do
        sleep 0.1
        begin
          make_request('/health')
          break
        rescue => e
          # Server not ready yet
          next
        end
      end
    end
  rescue Timeout::Error
    raise "Puma server failed to start within 30 seconds"
  end

  def make_request(path)
    uri = URI("#{base_url}#{path}")
    Net::HTTP.get_response(uri)
  end

  def collect_instance_values(requests:)
    values = []
    requests.times do
      response = make_request('/instance')
      expect(response.code).to eq('200')
      values << response.body.strip
    end
    values.uniq
  end

  def collect_instance_pid_correlations(requests:)
    correlations = []
    requests.times do
      instance_response = make_request('/instance')
      pid_response = make_request('/pid')

      expect(instance_response.code).to eq('200')
      expect(pid_response.code).to eq('200')

      correlations << {
        instance: instance_response.body.strip,
        pid: pid_response.body.strip.to_i
      }
    end
    correlations
  end
end
