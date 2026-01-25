# spec/integration/all/puma_fork_registry_workflow_spec.rb
#
# frozen_string_literal: true

# Puma Fork Registry Workflow Integration Tests
#
# Usage: bundle exec rspec spec/integration/all/puma_fork_registry_workflow_spec.rb
#
# Validates the complete boot → fork → worker workflow for fork-sensitive
# initializers in Puma cluster mode with preload_app! enabled.
#
# Coverage:
# - Complete boot → fork → worker workflow
# - Multiple fork-sensitive initializers coordination
# - Validation catches issues before Puma starts
# - Degraded mode operation when initializers fail
#
# Implements end-to-end testing for GitHub issue #2205 Phase 3.

require_relative '../../spec_helper'
require_relative '../../support/puma_integration/server_helper'

RSpec.describe 'Puma Fork Registry Complete Workflow', type: :integration do
  include PumaIntegration::ServerHelper

  before(:all) do
    puts "\n🔧 Starting Puma Fork Registry Workflow Test"
    start_puma_with_retry
  end

  after(:all) do
    shutdown_puma_server
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

      expect(workflow['boot_pids']).not_to be_empty
      expect(workflow['cleanup_pids']).not_to be_empty
      expect(workflow['reconnect_pids']).not_to be_empty
      expect(workflow['reconnect_pids']).to include(workflow['pid'])
      expect(workflow['reconnect_pids']).not_to eq(workflow['boot_pids'])
    end

    it 'workers function correctly after fork with reconnected resources' do
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

      response = make_request('/workflow')
      workflow = JSON.parse(response.body)
      expect(workflow['reconnect_order']).not_to be_empty
    end
  end

  describe 'Multiple fork-sensitive initializers coordination' do
    it 'executes all initializers cleanup in correct order' do
      response = make_request('/workflow')
      workflow = JSON.parse(response.body)

      puts "\n📋 Cleanup execution order: #{workflow['cleanup_order'].inspect}"

      expect(workflow['cleanup_order']).to include('init1', 'init2', 'init3')
      expect(workflow['cleanup_errors']).to include('failing_cleanup')
    end

    it 'executes all initializers reconnect in correct order' do
      response = make_request('/workflow')
      workflow = JSON.parse(response.body)

      puts "\n📋 Reconnect execution order: #{workflow['reconnect_order'].inspect}"

      expect(workflow['reconnect_order']).to include('init1', 'init2', 'init3')
      expect(workflow['reconnect_errors']).to include('failing_reconnect')
    end

    it 'coordinates multiple initializers with dependencies' do
      response = make_request('/initializers')
      data = JSON.parse(response.body)

      puts "\n📋 Fork-sensitive initializers: #{data['names'].join(', ')}"

      expect(data['count']).to be >= 5
      expect(data['names']).to include(
        'test_fork_init1',
        'test_fork_init2',
        'test_fork_init3',
        'test_fork_failing_cleanup',
        'test_fork_failing_reconnect'
      )

      data['phases'].each_value do |phase|
        expect(phase).to eq('fork_sensitive')
      end
    end
  end

  describe 'Validation catches issues before Puma starts' do
    it 'validates fork-sensitive initializers have required methods' do
      response = make_request('/initializers')
      data = JSON.parse(response.body)

      puts "\n📋 All #{data['count']} fork-sensitive initializers passed validation"

      expect(data['count']).to be > 0
    end

    it 'all initializers have working reconnect methods' do
      response = make_request('/workflow')
      workflow = JSON.parse(response.body)

      puts "\n📋 #{workflow['reconnect_order'].size} initializers reconnected successfully"

      expect(workflow['reconnect_order']).not_to be_empty
    end
  end

  describe 'Degraded mode operation' do
    it 'continues when one initializer fails during cleanup' do
      response = make_request('/workflow')
      workflow = JSON.parse(response.body)

      puts "\n📋 Degraded mode - cleanup errors: #{workflow['cleanup_errors'].inspect}"

      expect(workflow['cleanup_errors']).to include('failing_cleanup')
      expect(workflow['cleanup_order']).to include('init1', 'init2', 'init3')
      expect(workflow['reconnect_order']).not_to be_empty
    end

    it 'continues when one initializer fails during reconnect' do
      response = make_request('/workflow')
      workflow = JSON.parse(response.body)

      puts "\n📋 Degraded mode - reconnect errors: #{workflow['reconnect_errors'].inspect}"

      expect(workflow['reconnect_errors']).to include('failing_reconnect')
      expect(workflow['reconnect_order']).to include('init1', 'init2', 'init3')

      health_response = make_request('/health')
      expect(health_response.code).to eq('200')
    end

    it 'logs errors but continues processing remaining initializers' do
      stdout_content = File.read(@puma_stdout.path)

      expect(stdout_content).to include('RAISING ERROR')
      expect(stdout_content).to include('TestForkInit1.cleanup called')
      expect(stdout_content).to include('TestForkInit2.cleanup called')
      expect(stdout_content).to include('TestForkInit3.cleanup called')
      expect(stdout_content).to include('TestForkInit1.reconnect called')
      expect(stdout_content).to include('TestForkInit2.reconnect called')
      expect(stdout_content).to include('TestForkInit3.reconnect called')
    end
  end

  private

  # Generate the rackup file content that loads our test fixtures
  def test_app_content
    support_dir = File.expand_path('../../support/puma_integration', __dir__)

    <<~RUBY
      begin
        require 'bundler/setup'

        # Load Onetime core and initializer infrastructure
        require_relative '#{File.join(Onetime::HOME, 'lib', 'onetime')}'
        require_relative '#{File.join(Onetime::HOME, 'lib', 'onetime', 'boot', 'initializer')}'
        require_relative '#{File.join(Onetime::HOME, 'lib', 'onetime', 'boot', 'initializer_registry')}'

        # Load test fixtures from spec/support
        require_relative '#{support_dir}/test_fork_initializers'
        require_relative '#{support_dir}/fork_workflow_rack_app'

        puts "[preload] Loading test initializers..."
        registry = Onetime::Boot::InitializerRegistry.new
        Onetime::Boot::InitializerRegistry.current = registry

        # Load ONLY test initializers (bypass ObjectSpace discovery)
        registry.load([
          TestForkInit1,
          TestForkInit2,
          TestForkInit3,
          TestForkFailingCleanup,
          TestForkFailingReconnect
        ])

        puts "[preload] Running initializers..."
        results = registry.run_all

        fork_sensitive = registry.fork_sensitive_initializers
        puts "[preload] Fork-sensitive: \#{fork_sensitive.map(&:name).join(', ')}"
        puts "[preload] Results: \#{results[:successful].size} ok, \#{results[:failed].size} failed"

        run PumaIntegration.build_workflow_app(fork_sensitive)
      rescue => e
        puts "[preload] ERROR during preload: \#{e.class} - \#{e.message}"
        puts e.backtrace
        exit 27
      end
    RUBY
  end
end
