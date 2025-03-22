# support/sendgrid_test.rb

$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))

require 'onetime'
require 'onetime/app/mail/sendgrid_mailer'

Onetime.boot! :app

Onetime::Mail::SendGridMailer.setup

# Initialize mailer
mailer = Onetime::Mail::SendGridMailer.new "sender@example.com", "Test Sender"

# Send test email with sandbox mode enabled
response = mailer.send_email(
  "recipient@example.com",
  "Test Email Subject",
  "<p>This is a test html content.</p>",
  "This is a test text content.",
  true, # Enable sandbox mode
)

if response&.status_code == "200"
  puts "Email test successful - sandbox mode working"
  puts "Response: #{response.inspect}"
else
  puts "Email test failed"
  puts "Status: #{response&.status_code}"
  puts "Body: #{response&.body}"
end
