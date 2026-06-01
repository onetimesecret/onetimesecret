# apps/web/auth/spec/integration/full/internal_request_trace_spec.rb
#
# frozen_string_literal: true

# Trace: What actually happens during internal_request(:create_account)

require_relative '../../spec_helper'

RSpec.describe 'Trace: internal_request execution', type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.boot!(:test, force: true)
    Onetime::Application::Registry.prepare_application_registry
  end

  let(:test_suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:test_email) { "trace_#{test_suffix}@example.com" }
  let(:password) { 'TestPassword123!' }

  after do
    Auth::Database.connection[:accounts].where(email: test_email).delete rescue nil
    Onetime::Customer.find_by_email(test_email)&.destroy! rescue nil
  end

  it 'traces internal_request execution with debug hooks' do
    internal_class = Auth::Config.const_get(:InternalRequest)

    # Prepend a module to trace method calls
    trace_log = []

    tracer = Module.new do
      define_method(:after_create_account) do
        trace_log << "after_create_account called"
        super()
      end

      define_method(:_after_create_account) do
        trace_log << "_after_create_account called"
        super()
      end

      define_method(:before_create_account) do
        trace_log << "before_create_account called"
        super()
      end

      define_method(:save_account) do
        trace_log << "save_account called"
        result = super()
        trace_log << "save_account returned: #{result}"
        result
      end

      define_method(:create_account_response) do
        trace_log << "create_account_response called"
        super()
      end
    end

    # Temporarily prepend the tracer
    internal_class.prepend(tracer)

    puts "\n=== Calling internal_request(:create_account) ==="

    begin
      result = Auth::Config.create_account(
        login: test_email,
        password: password
      )
      puts "Result: #{result.inspect}"
    rescue => e
      puts "Error: #{e.class} - #{e.message}"
    end

    puts "\n=== Trace log ==="
    trace_log.each { |entry| puts "  #{entry}" }

    # Check what happened
    account = Auth::Database.connection[:accounts].where(email: test_email).first
    puts "\n=== Results ==="
    puts "Account created: #{!account.nil?}"

    customer = Onetime::Customer.find_by_email(test_email)
    puts "Customer created: #{!customer.nil?}"

    # The key question: was after_create_account called?
    puts "\n=== Analysis ==="
    if trace_log.include?("after_create_account called")
      puts "after_create_account WAS called"
      if trace_log.include?("_after_create_account called")
        puts "_after_create_account WAS called (the hook body)"
        if customer.nil?
          puts "BUT Customer was not created - error in hook logic?"
        end
      else
        puts "_after_create_account was NOT called - hook body skipped!"
      end
    else
      puts "after_create_account was NOT called at all!"
    end

    expect(trace_log).to include("save_account called")
  end
end
