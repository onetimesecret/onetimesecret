#!/usr/bin/env ruby
# Test script for email configuration
# Usage: ruby apps/web/auth/config/test_email_config.rb

require_relative '../../../lib/onetime'
require_relative 'email'

puts "Testing Email Configuration..."

# Test different providers
providers_to_test = %w[logger smtp sendgrid ses mailpit]

providers_to_test.each do |provider|
  puts "\n--- Testing #{provider.upcase} provider ---"

  begin
    ENV['EMAIL_PROVIDER'] = provider
    config = Auth::Config::Email::Configuration.new

    puts "✓ Provider: #{config.provider}"
    puts "✓ From: #{config.from_address}"
    puts "✓ Subject Prefix: #{config.subject_prefix}"
    puts "✓ Delivery Strategy: #{config.delivery_strategy.class}"

    # Test email delivery (will use logger for most providers without credentials)
    test_email = {
      to: 'test@example.com',
      subject: 'Test Email',
      body: 'This is a test email from the OneTimeSecret auth system.'
    }

    puts "✓ Attempting delivery..."
    config.deliver_email(test_email)
    puts "✓ Email delivery successful"

  rescue => e
    puts "✗ Error: #{e.message}"
  end
end

# Test auto-detection
puts "\n--- Testing Auto-Detection ---"
ENV.delete('EMAIL_PROVIDER')
config = Auth::Config::Email::Configuration.new
puts "Auto-detected provider: #{config.provider}"

puts "\nEmail configuration test complete!"
