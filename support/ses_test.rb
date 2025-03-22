# support/ses_test.rb

$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))

require 'onetime'
require 'onetime/app/mail/ses_mailer'

Onetime.boot! :app

Onetime::Mail::AmazonSESMailer.setup

# Initialize mailer
mailer = Onetime::Mail::AmazonSESMailer.new "sender@onetimesecret.com", "Test Sender"

# Send test email
response = mailer.send_email(
  "recipient@example.com",
  "AWS SES Test Email",
  "<p>This is a test email sent via Amazon SES.</p>"
)

if response&.message_id
  puts "Email test successful"
  puts "Message ID: #{response.message_id}"
else
  puts "Email test failed"
  puts "Response: #{response.inspect}"
end
