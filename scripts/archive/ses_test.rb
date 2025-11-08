# scripts/archive/ses_test.rb
#
# frozen_string_literal: true

#
# Test script for AWS SES email delivery in OnetimeSecret
# This utility verifies that Amazon SES is properly configured for sending emails

$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))

require 'onetime'
require 'onetime/mail/mailer/ses_mailer'

# Initialize the application environment
Onetime.boot! :app

# Setup the SES mailer with AWS credentials from environment
Onetime::Mail::Mailer::SESMailer.setup

# Initialize mailer with sender information
mailer = Onetime::Mail::Mailer::SESMailer.new "sender@onetimesecret.com", "Test Sender"

# Send test email with HTML content
response = mailer.send_email(
  "recipient@example.com",
  "AWS SES Test Email",
  "<p>This is a test email sent via Amazon SES.</p>",
)

# Check and display the results
if response&.message_id
  puts "Email test successful"
  puts "Message ID: #{response.message_id}"
else
  puts "Email test failed"
  puts "Response: #{response.inspect}"
end

# === USAGE INSTRUCTIONS ===
#
# 1. Ensure AWS credentials are properly configured in your environment:
#    - Either via environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
#    - Or through AWS credential file (~/.aws/credentials)
#    - Or via IAM roles if running on EC2/ECS
#
# 2. Update sender and recipient email addresses in the script if needed:
#    - Default sender: sender@onetimesecret.com
#    - Default recipient: recipient@example.com
#
# 3. Run the script:
#
#    $ ruby support/ses_test.rb
#
# 4. Check the output to verify if the email was sent successfully
#    - A successful test will display a Message ID
#    - A failed test will show error details
#
# Note: The sender email must be verified in your AWS SES console
# if your account is still in the SES sandbox.
