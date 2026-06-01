# apps/web/auth/spec/integration/full/internal_request_hook_body_trace_spec.rb
#
# frozen_string_literal: true

# Trace: What's happening inside the after_create_account hook body?

require_relative '../../spec_helper'

RSpec.describe 'Trace: Hook body execution', type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.boot!(:test, force: true)
    Onetime::Application::Registry.prepare_application_registry
  end

  let(:test_suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:test_email) { "hook_trace_#{test_suffix}@example.com" }
  let(:password) { 'TestPassword123!' }

  after do
    Auth::Database.connection[:accounts].where(email: test_email).delete rescue nil
    Onetime::Customer.find_by_email(test_email)&.destroy! rescue nil
  end

  it 'traces hook body execution' do
    internal_class = Auth::Config.const_get(:InternalRequest)

    # Completely replace _after_create_account to trace exactly what happens
    tracer = Module.new do
      define_method(:_after_create_account) do
        puts "\n[HOOK TRACE] _after_create_account body starting"
        puts "[HOOK TRACE]   account_id: #{account_id.inspect}"
        puts "[HOOK TRACE]   account: #{account.inspect}"
        puts "[HOOK TRACE]   respond_to?(:request): #{respond_to?(:request)}"

        begin
          req = request
          puts "[HOOK TRACE]   request: #{req.class}"
          puts "[HOOK TRACE]   request.env class: #{req.env.class}" if req.respond_to?(:env)
        rescue => e
          puts "[HOOK TRACE]   request access error: #{e.class} - #{e.message}"
        end

        puts "[HOOK TRACE]   param_or_nil('invite_token'): #{param_or_nil('invite_token').inspect}"

        # Now try to call the original hook
        puts "[HOOK TRACE] Calling super..."
        begin
          super()
          puts "[HOOK TRACE] super completed normally"
        rescue => e
          puts "[HOOK TRACE] super raised: #{e.class} - #{e.message}"
          puts "[HOOK TRACE] backtrace:"
          e.backtrace.first(10).each { |line| puts "  #{line}" }
          raise
        end

        puts "[HOOK TRACE] _after_create_account body complete"
      end
    end

    internal_class.prepend(tracer)

    puts "\n=== Calling internal_request(:create_account) ==="
    result = Auth::Config.create_account(
      login: test_email,
      password: password
    )
    puts "Result: #{result.inspect}"

    account = Auth::Database.connection[:accounts].where(email: test_email).first
    puts "\nAccount: #{account.inspect}"

    customer = Onetime::Customer.find_by_email(test_email)
    puts "Customer: #{customer.inspect}"

    expect(account).not_to be_nil
  end
end
