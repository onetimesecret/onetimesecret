# apps/web/auth/spec/integration/full/internal_request_safe_execute_trace_spec.rb
#
# frozen_string_literal: true

# Trace: Is safe_execute even being called?

require_relative '../../spec_helper'

RSpec.describe 'Trace: safe_execute calls', type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.boot!(:test, force: true)
    Onetime::Application::Registry.prepare_application_registry
  end

  let(:test_suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:test_email) { "se_trace_#{test_suffix}@example.com" }
  let(:password) { 'TestPassword123!' }

  after do
    Auth::Database.connection[:accounts].where(email: test_email).delete rescue nil
    Onetime::Customer.find_by_email(test_email)&.destroy! rescue nil
  end

  it 'traces safe_execute calls' do
    safe_execute_calls = []

    # Save original
    original_safe_execute = Onetime::ErrorHandler.method(:safe_execute)

    # Replace with tracer
    Onetime::ErrorHandler.define_singleton_method(:safe_execute) do |operation, **context, &block|
      puts "[SE TRACE] safe_execute called: #{operation}"
      puts "[SE TRACE]   context: #{context.inspect}"
      safe_execute_calls << { operation: operation, context: context }

      begin
        result = block.call
        puts "[SE TRACE]   block returned: #{result.inspect}"
        puts "[SE TRACE]   result.is_a?(Onetime::Customer): #{result.is_a?(Onetime::Customer)}" if result
        result
      rescue StandardError => ex
        puts "[SE TRACE]   block raised: #{ex.class} - #{ex.message}"
        nil
      end
    end

    begin
      puts "\n=== Calling internal_request(:create_account) ==="
      result = Auth::Config.create_account(
        login: test_email,
        password: password
      )
      puts "Result: #{result.inspect}"

      puts "\n=== safe_execute calls ==="
      safe_execute_calls.each_with_index do |call, i|
        puts "#{i + 1}. #{call[:operation]} - #{call[:context]}"
      end

      account = Auth::Database.connection[:accounts].where(email: test_email).first
      puts "\nAccount: #{account.inspect}"

      customer = Onetime::Customer.find_by_email(test_email)
      puts "Customer: #{customer.inspect}"
    ensure
      # Restore
      Onetime::ErrorHandler.define_singleton_method(:safe_execute, original_safe_execute)
    end

    # Check if safe_execute was called
    create_customer_call = safe_execute_calls.find { |c| c[:operation] == 'create_customer' }
    expect(create_customer_call).not_to be_nil, "Expected safe_execute('create_customer') to be called"
  end
end
