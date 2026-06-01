# apps/web/auth/spec/integration/full/internal_request_error_trace_spec.rb
#
# frozen_string_literal: true

# Trace: What error is safe_execute swallowing?

require_relative '../../spec_helper'

RSpec.describe 'Trace: CreateCustomer error', type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.boot!(:test, force: true)
    Onetime::Application::Registry.prepare_application_registry
  end

  let(:test_suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:test_email) { "trace_err_#{test_suffix}@example.com" }
  let(:password) { 'TestPassword123!' }

  after do
    Auth::Database.connection[:accounts].where(email: test_email).delete rescue nil
    Onetime::Customer.find_by_email(test_email)&.destroy! rescue nil
  end

  it 'confirms safe_execute operations complete without errors' do
    # After the hook-collision fix (#3275), the after_create_account hook runs
    # correctly and Customer creation succeeds. This test verifies that
    # safe_execute operations complete without catching errors.
    #
    # Previously, this test expected errors because billing.rb's hook overwrote
    # account.rb's hook, causing various failures that safe_execute silently
    # swallowed.
    errors_caught = []

    # Monkey-patch safe_execute to capture any errors
    original_safe_execute = Onetime::ErrorHandler.method(:safe_execute)

    Onetime::ErrorHandler.define_singleton_method(:safe_execute) do |operation, **context, &block|
      begin
        block.call
      rescue StandardError => ex
        errors_caught << {
          operation: operation,
          error_class: ex.class.name,
          message: ex.message,
          backtrace: ex.backtrace.first(5)
        }
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

      puts "\n=== Errors caught by safe_execute ==="
      if errors_caught.empty?
        puts "No errors caught - all operations succeeded!"
      else
        errors_caught.each do |err|
          puts "Operation: #{err[:operation]}"
          puts "Error: #{err[:error_class]}: #{err[:message]}"
          puts "Backtrace:"
          err[:backtrace].each { |line| puts "  #{line}" }
          puts
        end
      end

      account = Auth::Database.connection[:accounts].where(email: test_email).first
      puts "\n=== Results ==="
      puts "Account created: #{!account.nil?}"
      puts "Account status_id: #{account[:status_id]}" if account

      customer = Onetime::Customer.find_by_email(test_email)
      puts "Customer created: #{!customer.nil?}"
    ensure
      # Restore original method
      Onetime::ErrorHandler.define_singleton_method(:safe_execute, original_safe_execute)
    end

    # With the hook-collision fix, no errors should be caught — all operations succeed
    expect(errors_caught).to be_empty, <<~MSG
      Unexpected errors in safe_execute operations: #{errors_caught.map { |e| e[:operation] }.join(', ')}
      This may indicate a regression in the hook chain or a new failure mode.
    MSG

    # Both Account and Customer should exist
    account = Auth::Database.connection[:accounts].where(email: test_email).first
    customer = Onetime::Customer.find_by_email(test_email)
    expect(account).not_to be_nil
    expect(customer).not_to be_nil
  end
end
