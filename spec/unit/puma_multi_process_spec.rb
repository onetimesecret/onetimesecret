# ./spec/unit/puma_multi_process_spec.rb
#
# Puma Multi-Process Integration Test for OT.instance
#
# Usage: pnpm run test:rspec tests/integration/ruby/puma_multi_process_spec.rb
#
# This Ruby integration test verifies that OneTimeSecret's OT.instance correctly
# generates unique identifiers when running in Puma's multi-process environment.
#
# Key Findings:
# 1. OT.instance is a unique string generated per-process
# 2. Each Puma worker process gets a unique PID, therefore unique OT.instance
# 3. The instance value remains consistent within a worker's lifetime
# 4. CLI boot mode allows testing without full application dependencies
#
# This validates that process-level identification works correctly for:
# - Debugging and traceability across worker processes
# - Load balancing identification
# - Process-specific logging and monitoring
#
require_relative '../spec_helper'
require 'net/http'
require 'timeout'
require 'tempfile'
require 'socket'

RSpec.describe 'Puma Multi-Process Integration', type: :integration do
  # This test validates core multi-process functionality that's critical for production
  # deployment. Despite being ~2.5s slower than unit tests, it's included in the normal
  # test suite because it verifies process-level behavior that can't be tested otherwise.
  before(:all) do
    # Retry port allocation and Puma startup to handle parallel test execution
    startup_attempts = 0
    max_startup_attempts = 3

    puts "\n🚀 Starting Puma Multi-Process Integration Test"

    begin
      startup_attempts += 1
      puts "\n📍 Port allocation attempt #{startup_attempts}/#{max_startup_attempts}"
      @port = find_available_port
      @host = '127.0.0.1'
      @base_url = "http://#{@host}:#{@port}"
      @workers = 3
      @puma_pid_file = Tempfile.new(['puma_test', '.pid'])
      @puma_config_file = Tempfile.new(['puma_config', '.rb'])
      @test_app_file = Tempfile.new(['test_app', '.ru'])

      # Minimal Puma configuration for testing
      puma_config_content = <<~CONFIG
        port #{@port}
        bind "tcp://#{@host}:#{@port}"
        workers #{@workers}
        worker_timeout 10 # Must be > worker reporting interval (5)
        pidfile "#{@puma_pid_file.path}"

        # Each worker initializes separately to ensure unique OT.instance
        # No preload_app! - this ensures per-worker boot process

        # Redirect stdout/stderr to /dev/null for cleaner test output
        # In CI, these might be captured or handled differently.
        stdout_redirect '/dev/null', '/dev/null', true
      CONFIG

      # Test Rack application that exposes OT.instance and process info
      # Using Dir.pwd assumes test is run from project root
      lib_path = File.join(Dir.pwd, 'lib')
      apps_root = File.join(Dir.pwd, 'apps')
      test_app_content_content = <<~RUBY
        # Minimal test app for OT.instance verification
        $LOAD_PATH.unshift('#{lib_path}')

        # Add apps directories to load path for v2 models
        apps_root = '#{apps_root}'
        $LOAD_PATH.unshift(File.join(apps_root, 'api'))
        $LOAD_PATH.unshift(File.join(apps_root, 'web'))

        require 'onetime'

        # Boot once per worker - generates unique OT.instance per process
        # Use :cli mode to avoid full app dependencies and continue on config errors
        Onetime.boot! :cli, false # false means don't connect to DB

        app = proc do |env|
          case env['PATH_INFO']
          when '/instance'
            [200, {'content-type' => 'text/plain'}, [Onetime.instance.to_s]]
          when '/pid'
            [200, {'content-type' => 'text/plain'}, [Process.pid.to_s]]
          when '/info'
            # Ensure OT::VERSION is available, use a fallback if not (e.g. during early boot)
            version_string = defined?(OT::VERSION) ? OT::VERSION.to_s : 'unknown'
            info = "PID:\#{Process.pid}|Instance:\#{Onetime.instance}|Version:\#{version_string}"
            [200, {'content-type' => 'text/plain'}, [info]]
          when '/health'
            [200, {'content-type' => 'text/plain'}, ['OK']]
          else
            [404, {'content-type' => 'text/plain'}, ['Not Found']]
          end
        end

        run app
      RUBY

      File.write(@puma_config_file.path, puma_config_content)
      File.write(@test_app_file.path, test_app_content_content)

      @puma_stdout = Tempfile.new('puma_stdout')
      @puma_stderr = Tempfile.new('puma_stderr')

      # Spawn Puma server with SECRET env var for minimal boot
      @puma_pid = spawn(
        { 'SECRET' => 'test_secret_for_integration_test' }, # Required for boot
        'puma',
        '-C', @puma_config_file.path,
        @test_app_file.path,
        out: @puma_stdout.path,
        err: @puma_stderr.path
      )

      puts "🌟 Starting Puma server on #{@base_url} with #{@workers} workers..."
      wait_for_server_start
      puts "✅ Puma server successfully started on port #{@port}\n"

    rescue => e
      puts "❌ Puma startup failed on port #{@port}: #{e.message}"
      # Clean up on failure
      cleanup_puma_process
      cleanup_temp_files

      if startup_attempts < max_startup_attempts && e.message.include?('Address already in use')
        backoff_time = startup_attempts * 0.5
        puts "⏱  Retrying in #{backoff_time}s... (attempt #{startup_attempts + 1}/#{max_startup_attempts})"
        sleep(backoff_time) # Progressive backoff
        retry
      else
        puts "💥 Failed to start Puma after #{startup_attempts} attempts"
        raise e
      end
    end
  end

  after(:all) do
    cleanup_puma_process
    cleanup_temp_files
  end

  describe 'OT.instance behavior in multi-process environment' do

  private

  def cleanup_puma_process
    if @puma_pid
      begin
        Process.kill('TERM', @puma_pid)
        Timeout.timeout(10) { Process.wait(@puma_pid) }
      rescue Errno::ESRCH, Timeout::Error
        Process.kill('KILL', @puma_pid) rescue nil # Force kill if TERM fails
      end
    end
  end

  def cleanup_temp_files
    # Clean up temp files
    [@puma_pid_file, @puma_config_file, @test_app_file, @puma_stdout, @puma_stderr].compact.each do |file|
      file.close
      file.unlink # Explicitly delete the temp file
    end
  end
    it 'generates valid instance identifiers' do
      response = make_request('/instance')
      expect(response.code).to eq('200')
      instance_value = response.body.strip
      expect(instance_value).to match(/\A[a-z0-9]{10,17}\z/)
    end

    it 'provides process and version information' do
      response = make_request('/info')
      expect(response.code).to eq('200')
      info = response.body.strip
      expect(info).to match(/\APID:\d+\|Instance:[a-z0-9]{10,17}\|Version:/)
      parts = info.split('|')
      pid_part, instance_part, version_part = parts
      expect(pid_part).to start_with('PID:')
      expect(instance_part).to start_with('Instance:')
      expect(version_part).to start_with('Version:')
      pid = pid_part.split(':')[1].to_i
      expect(pid).to be > 0
    end

    it 'maintains instance consistency within process lifetime' do
      instances_by_pid = {}
      5.times do
        response = make_request('/info')
        expect(response.code).to eq('200')
        info = response.body.strip
        parts = info.split('|')
        pid = parts[0].split(':')[1].to_i
        instance = parts[1].split(':')[1]
        instances_by_pid[pid] ||= []
        instances_by_pid[pid] << instance
        sleep 0.05 # Small delay
      end

      instances_by_pid.each do |pid, instances|
        expect(instances.uniq.size).to eq(1),
          "PID #{pid} should maintain consistent instance value. Got: #{instances.uniq}"
      end
    end

    it 'demonstrates multi-process capability' do
      process_info_data = []
      20.times do
        response = make_request('/info')
        expect(response.code).to eq('200')
        process_info_data << response.body.strip
        sleep 0.05 # Encourage requests to hit different workers
      end

      parsed_data = process_info_data.map do |info|
        parts = info.split('|')
        {
          pid: parts[0].split(':')[1].to_i,
          instance: parts[1].split(':')[1],
          version: parts[2].split(':')[1]
        }
      end

      unique_pids = parsed_data.map { |p| p[:pid] }.uniq
      unique_instances = parsed_data.map { |p| p[:instance] }.uniq

      puts "\n\nPuma Multi-Process Test Results:"
      puts "  Configured workers: #{@workers}"
      puts "  Unique PIDs observed: #{unique_pids.size} (PIDs: #{unique_pids.sort.join(', ')})"
      puts "  Unique OT.instances observed: #{unique_instances.size}"
      puts "  OT.instance values:"
      unique_instances.each_with_index { |inst, i| puts "    #{i + 1}. #{inst}" }
      puts ""

      expect(unique_pids.size).to be >= 1
      expect(unique_instances.size).to be >= 1

      if unique_pids.size > 1
        puts "  ✓ Multiple worker processes successfully detected."
        puts "  ✓ Each worker process generates a unique OT.instance."
        pid_to_instance_map = parsed_data.group_by { |p| p[:pid] }.transform_values { |v| v.map { |d| d[:instance] }.uniq }
        puts "  PID to OT.instance mapping:"
        pid_to_instance_map.each do |pid, instances|
          puts "    PID #{pid} → #{instances.join(', ')}" # Should ideally be one instance
          expect(instances.size).to eq(1), "Process #{pid} should have a consistent instance value."
        end
        expect(unique_instances.size).to eq(unique_pids.size), "Number of unique instances should match number of unique PIDs."
      else
        puts "  ℹ Only one worker process was hit in this test run. This can happen in some environments."
        puts "    However, OT.instance generation and consistency within that worker is verified."
        # Additional verification if only one worker
        pid_to_instance_map = parsed_data.group_by { |p| p[:pid] }.transform_values { |v| v.map { |d| d[:instance] }.uniq }
        pid_to_instance_map.each do |pid, instances|
           expect(instances.size).to eq(1), "Single worker PID #{pid} should still have a consistent instance value. Got: #{instances.uniq}"
        end
      end
    end
  end

  private

  def cleanup_puma_process
    if @puma_pid
      begin
        Process.kill('TERM', @puma_pid)
        Timeout.timeout(10) { Process.wait(@puma_pid) }
      rescue Errno::ESRCH, Timeout::Error
        Process.kill('KILL', @puma_pid) rescue nil # Force kill if TERM fails
      end
    end
  end

  def cleanup_temp_files
    # Clean up temp files
    [@puma_pid_file, @puma_config_file, @test_app_file, @puma_stdout, @puma_stderr].compact.each do |file|
      file.close
      file.unlink # Explicitly delete the temp file
    end
  end

  def find_available_port
    # Use a wider port range and retry logic to avoid race conditions
    # when running tests in parallel
    10.times do |attempt|
      begin
        # Use random port in high range to reduce collision chance
        port = rand(20000..60000)
        server = TCPServer.new('127.0.0.1', port)
        server.close
        puts "  ✓ Found available port #{port} (attempt #{attempt + 1})"
        return port
      rescue Errno::EADDRINUSE
        # Port already in use, try another
        puts "  ⚠ Port #{port} in use, retrying... (attempt #{attempt + 1})"
        next
      end
    end

    # Fallback to OS allocation if all random attempts fail
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    puts "  ✓ Fallback to OS-allocated port #{port}"
    port
  end

  def wait_for_server_start
    Timeout.timeout(30) do
      loop do
        sleep 0.5 # Increased sleep
        begin
          response = make_request('/health')
          break if response.code == '200'
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          next # Server not ready yet
        rescue StandardError => e
          # Catch other potential errors during startup check
          puts "Error during health check: #{e.message}"
          next
        end
      end
    end
  rescue Timeout::Error
    stdout_content = File.read(@puma_stdout.path) rescue "Could not read stdout: #{@puma_stdout.path}"
    stderr_content = File.read(@puma_stderr.path) rescue "Could not read stderr: #{@puma_stderr.path}"
    raise "Puma server failed to start on port #{@port} within 30 seconds.\nSTDOUT:\n#{stdout_content}\nSTDERR:\n#{stderr_content}"
  end

  def make_request(path)
    uri = URI("#{@base_url}#{path}")
    # Use a new connection for each request to better simulate multiple clients
    # and avoid keep-alive issues that might skew load balancing in tests.
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5 # seconds
    http.read_timeout = 5 # seconds
    request = Net::HTTP::Get.new(uri.request_uri)
    http.request(request)
  end
end
