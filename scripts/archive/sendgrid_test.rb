# scripts/archive/sendgrid_test.rb
#
# frozen_string_literal: true

#
# Test script for SendGrid email delivery in OnetimeSecret
# This utility verifies that SendGrid API integration is properly configured

$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))

require 'onetime'
require 'onetime/mail/mailer/sendgrid_mailer'

# Initialize the application environment
Onetime.boot! :app

# Setup the SendGrid mailer with API key from environment
Onetime::Mail::Mailer::SendGridMailer.setup

# Initialize mailer with sender information
mailer = Onetime::Mail::Mailer::SendGridMailer.new "sender@example.com", "Test Sender"

# Send test email with sandbox mode enabled
response = mailer.send_email(
  "recipient@example.com",
  "Test Email Subject",
  "<p>This is a test html content.</p>",
  "This is a test text content.",
  true, # Enable sandbox mode
)

# Check and display the results
if response&.status_code == "200"
  puts "Email test successful - sandbox mode working"
  puts "Response: #{response.inspect}"
else
  puts "Email test failed"
  puts "Status: #{response&.status_code}"
  puts "Body: #{response&.body}"
end

# === USAGE INSTRUCTIONS ===
#
# 1. Ensure SendGrid API key is properly configured in your environment:
#    - Set the SENDGRID_API_KEY environment variable
#
# 2. Update sender and recipient email addresses in the script if needed:
#    - Default sender: sender@example.com
#    - Default recipient: recipient@example.com
#
# 3. Run the script:
#
#    $ ruby support/sendgrid_test.rb
#
# 4. Check the output to verify if the email was sent successfully
#    - A successful test will display a 200 status code
#    - A failed test will show error details
#
# Note: This test uses SendGrid's sandbox mode by default, which validates
# the request without actually sending an email. Set the sandbox parameter
# to false to send a real email:
#
# response = mailer.send_email(
#   "recipient@example.com",
#   "Test Email Subject",
#   "<p>This is a test html content.</p>",
#   "This is a test text content.",
#   false, # Disable sandbox mode to send real email
# )
