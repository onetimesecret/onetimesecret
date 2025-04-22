# support/smtp_test.rb
#
# Basic SMTP checker for OneTimeSecret
# This utility helps test SMTP email delivery using configured environment variables

# frozen_string_literal: true
# typed: false

$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))

require 'net/smtp'
require 'dotenv'

Dotenv.load

timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')

# Define the email parameters
subject = 'Test Email'
message = 'This is a test email sent from the Ruby script.'
from_email = ENV.fetch('FROM_EMAIL', 'support@example.com')
to_email = ENV.fetch('TO_EMAIL', 'recipient@example.com')

# SMTP server configuration
smtp_host = ENV.fetch('SMTP_HOST')
smtp_port = ENV.fetch('SMTP_PORT', 587)
smtp_username = ENV.fetch('SMTP_USERNAME')
smtp_password = ENV.fetch('SMTP_PASSWORD')

# Prepare raw smtp message
msg_str = <<~MAIL
  From: #{from_email}
  To: #{to_email}
  Subject: #{subject} at #{timestamp}
  Date: #{Time.now.strftime('%a, %b %d %Y %H:%M:%S %z')}

  #{message}
MAIL

# Use Net::SMTP to send the email
mailer = Net::SMTP.new(smtp_host, smtp_port)
mailer.enable_starttls

puts "Using account #{smtp_username} on host #{smtp_host} (destination: #{to_email})"

begin
  mailer.start(smtp_host, smtp_username, smtp_password, :login) do |smtp|
    response = smtp.send_message(msg_str, from_email, to_email)
    puts "Message sent successfully. Status: #{response.status}"
  end
rescue Net::SMTPError, StandardError => e
  puts "Failed to send message: #{e.message}"
  puts e.message
  exit(1)
end

# === USAGE INSTRUCTIONS ===
#
# 1. Update the .env file in the root project directory with your SMTP settings:
#
#    SMTP_HOST=smtp.example.com
#    SMTP_PORT=587
#    SMTP_USERNAME=your_username
#    SMTP_PASSWORD=your_password
#    FROM_EMAIL=sender@example.com
#    TO_EMAIL=recipient@example.com
#
# 2. Run the script:
#
#    $ ruby support/smtp_test.rb
#
# 3. Check the output to verify if the email was sent successfully
#
# 4. Custom parameters can be set directly in the .env file or by modifying
#    the variables at the top of this script.
