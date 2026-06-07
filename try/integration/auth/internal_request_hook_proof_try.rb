# try/integration/auth/internal_request_hook_proof_try.rb
#
# frozen_string_literal: true

# Proof: Does Rodauth's internal_request(:create_account) call after_create_account?
#
# Run via rspec environment (already configured):
#   source .env.test && AUTHENTICATION_MODE=full bundle exec rspec -r ./try/integration/auth/internal_request_hook_proof_try.rb --dry-run

require 'bundler/setup'
require 'onetime'
require 'onetime/application/registry'
require 'onetime/auth_config'

Onetime.boot!(:test, force: true)
Onetime::Application::Registry.prepare_application_registry

test_email = "proof_#{Time.now.to_i}_#{rand(1000)}@example.com"
password = 'TestPassword123!'

puts "\n=== PROOF: internal_request(:create_account) hook invocation ==="
puts "Test email: #{test_email}"
puts "Auth::Config.respond_to?(:create_account): #{Auth::Config.respond_to?(:create_account)}"
puts "Auth::Config.private_method_defined?(:after_create_account): #{Auth::Config.private_method_defined?(:after_create_account)}"

begin
  puts "\nCalling Auth::Config.create_account..."
  result = Auth::Config.create_account(
    login: test_email,
    password: password
  )
  puts "create_account returned: #{result.inspect}"
rescue Rodauth::InternalRequestError => e
  puts "InternalRequestError: #{e.message}"
  puts "  field_errors: #{e.field_errors}" if e.respond_to?(:field_errors)
rescue StandardError => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

puts "\n=== CHECKING RESULTS ==="

# Check if account was created in SQL
account = Auth::Database.connection[:accounts].where(email: test_email).first
puts "Account created in SQL: #{!account.nil?}"
if account
  puts "  id: #{account[:id]}"
  puts "  email: #{account[:email]}"
  puts "  status_id: #{account[:status_id]}"
  puts "  external_id: #{account[:external_id].inspect}"
end

# Check if Customer was created in Redis (by the hook)
customer = Onetime::Customer.find_by_email(test_email)
puts "Customer created in Redis: #{!customer.nil?}"
if customer
  puts "  custid: #{customer.custid}"
  puts "  email: #{customer.email}"
  puts "  external_id: #{customer.external_id}"
end

# Cleanup
Auth::Database.connection[:accounts].where(email: test_email).delete if account
customer&.destroy! rescue nil

puts "\n=== CONCLUSION ==="
if customer
  puts "✅ PASS: after_create_account hook WAS called (Customer exists)"
else
  puts "❌ FAIL: after_create_account hook was NOT called (no Customer)"
  puts "   Account exists in SQL but Customer missing from Redis."
  puts "   This proves internal_request bypasses the hook."
end
