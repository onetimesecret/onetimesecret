# frozen_string_literal: true

# spec/support/stripe_mock_server.rb
#
# Manages the stripe-mock Go server for testing.
# Uses official Stripe mock server: https://github.com/stripe/stripe-mock
#
# Installation:
#   brew install stripe/stripe-mock/stripe-mock  (macOS)
#   go install github.com/stripe/stripe-mock@latest  (via Go)
#
# The server runs on port 12111 by default (stripe-mock's default port).
# Tests will automatically point to this mock server instead of live Stripe API.

require 'net/http'
require 'timeout'

module StripeMockServer
  class Error < StandardError; end

  class << self
    attr_reader :pid, :port

    # Start the stripe-mock server
    def start
      @port = ENV.fetch('STRIPE_MOCK_PORT', 12_111)

      return if running?

      # Find stripe-mock binary
      stripe_mock_bin = find_stripe_mock_binary
      unless stripe_mock_bin
        raise Error, <<~MSG
          stripe-mock is not installed. Install with:
            brew install stripe/stripe-mock/stripe-mock  (macOS)
            go install github.com/stripe/stripe-mock@latest  (via Go)
        MSG
      end

      # Start the server
      # Note: We don't use -strict-version-check to allow minor version drift
      # between Stripe SDK and stripe-mock's OpenAPI spec
      @pid = spawn(stripe_mock_bin, '-port', @port.to_s,
                   out: '/dev/null', err: '/dev/null')

      # Detach so it doesn't block
      Process.detach(@pid)

      # Wait for server to be ready (max 5 seconds)
      wait_until_ready!

      puts "stripe-mock server started on port #{@port} (PID: #{@pid})"
    rescue StandardError => e
      stop if @pid
      raise Error, "Failed to start stripe-mock: #{e.message}"
    end

    # Stop the stripe-mock server
    def stop
      return unless @pid

      begin
        Process.kill('TERM', @pid)
        Process.wait(@pid, Process::WNOHANG)
        puts "stripe-mock server stopped (PID: #{@pid})"
      rescue Errno::ESRCH, Errno::ECHILD
        # Process already dead
      ensure
        @pid = nil
      end
    end

    # Reset stripe-mock state (clears all data)
    def reset!
      return unless running?

      uri = URI("http://localhost:#{@port}/")
      req = Net::HTTP::Delete.new('/')

      Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(req)
      end
    rescue StandardError => e
      warn "Failed to reset stripe-mock: #{e.message}"
    end

    # Check if stripe-mock server is running
    def running?
      return false unless @pid

      uri = URI("http://localhost:#{@port}/")
      Net::HTTP.get(uri)
      true
    rescue StandardError
      false
    end

    # Configure Stripe client to use mock server
    def configure_stripe_client!
      require 'stripe'
      Stripe.api_base = "http://localhost:#{@port}"
      Stripe.api_key = 'sk_test_mock' # Mock key
    end

    private

    def find_stripe_mock_binary
      # Check if stripe-mock is in PATH
      return 'stripe-mock' if system('which stripe-mock > /dev/null 2>&1')

      # Check common Go installation location
      go_bin = File.expand_path('~/go/bin/stripe-mock')
      return go_bin if File.executable?(go_bin)

      nil
    end

    def wait_until_ready!
      Timeout.timeout(5) do
        loop do
          break if running?
          sleep 0.1
        end
      end
    rescue Timeout::Error
      raise Error, 'stripe-mock server failed to start within 5 seconds'
    end
  end
end
