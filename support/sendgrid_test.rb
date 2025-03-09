# support/sendgrid_test.rb

$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))

require 'onetime'
require 'onetime/app/mail/sendgrid_mailer'

Onetime.boot! :app

Onetime::App::Mail::SendGridMailer.setup

# Initialize mailer
mailer = Onetime::App::Mail::SendGridMailer.new "sender@example.com"
mailer.fromname = "Test Sender"

# Send test email with sandbox mode enabled
response = mailer.send_email(
  "recipient@example.com",
  "Test Email Subject",
  "<p>This is a test email content.</p>",
  true # Enable sandbox mode
)

if response&.status_code == "200"
  puts "Email test successful - sandbox mode working"
  puts "Response: #{response.inspect}"
else
  puts "Email test failed"
  puts "Status: #{response&.status_code}"
  puts "Body: #{response&.body}"
end
