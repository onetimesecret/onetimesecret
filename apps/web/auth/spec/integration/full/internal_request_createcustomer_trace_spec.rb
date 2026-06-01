# apps/web/auth/spec/integration/full/internal_request_createcustomer_trace_spec.rb
#
# frozen_string_literal: true

# Trace: What does CreateCustomer actually return?

require_relative '../../spec_helper'

RSpec.describe 'Trace: CreateCustomer return value', type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.boot!(:test, force: true)
    Onetime::Application::Registry.prepare_application_registry
  end

  let(:test_suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:test_email) { "cc_trace_#{test_suffix}@example.com" }
  let(:password) { 'TestPassword123!' }

  after do
    Auth::Database.connection[:accounts].where(email: test_email).delete rescue nil
    Onetime::Customer.find_by_email(test_email)&.destroy! rescue nil
  end

  it 'traces CreateCustomer return value during internal_request' do
    create_customer_calls = []

    # Wrap CreateCustomer#call
    original_call = Auth::Operations::CreateCustomer.instance_method(:call)

    Auth::Operations::CreateCustomer.define_method(:call) do
      puts "[TRACE] CreateCustomer#call starting"
      puts "[TRACE]   account_id: #{@account_id}"
      puts "[TRACE]   account: #{@account.inspect}"
      puts "[TRACE]   db: #{@db.class}"
      puts "[TRACE]   provisioning_origin: #{@provisioning_origin}"

      result = original_call.bind(self).call

      puts "[TRACE] CreateCustomer#call returned: #{result.inspect}"
      puts "[TRACE]   result.class: #{result.class}"
      puts "[TRACE]   result.is_a?(Onetime::Customer): #{result.is_a?(Onetime::Customer)}"

      create_customer_calls << {
        account_id: @account_id,
        account: @account.dup,
        result: result,
        result_class: result.class.name
      }

      result
    end

    begin
      puts "\n=== Calling internal_request(:create_account) ==="
      result = Auth::Config.create_account(
        login: test_email,
        password: password
      )
      puts "internal_request result: #{result.inspect}"

      puts "\n=== CreateCustomer calls ==="
      create_customer_calls.each_with_index do |call, i|
        puts "Call #{i + 1}:"
        puts "  account_id: #{call[:account_id]}"
        puts "  account: #{call[:account]}"
        puts "  result: #{call[:result].inspect}"
        puts "  result_class: #{call[:result_class]}"
      end

      account = Auth::Database.connection[:accounts].where(email: test_email).first
      puts "\n=== Final state ==="
      puts "Account: #{account.inspect}"

      customer = Onetime::Customer.find_by_email(test_email)
      puts "Customer: #{customer.inspect}"
    ensure
      # Restore original method
      Auth::Operations::CreateCustomer.define_method(:call, original_call)
    end

    expect(create_customer_calls).not_to be_empty
  end
end
