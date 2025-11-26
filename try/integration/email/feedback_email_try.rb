# try/integration/email/feedback_email_try.rb
#
# frozen_string_literal: true

# Tests the FeedbackEmail template for user feedback submissions.
# Uses Logger backend for safe testing without external calls.

require_relative '../../support/test_helpers'

# Force logger mode before loading anything
ENV['EMAILER_MODE'] = 'logger'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'

# Force config reload to pick up EMAILER_MODE env var
Onetime::Config.load

# Reset mailer to ensure clean state with new config
Onetime::Mail::Mailer.reset!

# Setup test data
@feedback_email = 'feedback-user@example.com'
@feedback_message = "This is a test feedback message.\nIt has multiple lines.\nThanks for the service!"
@feedback_domain = 'custom.onetimesecret.com'

# TRYOUTS

## FeedbackEmail template class exists
defined?(Onetime::Mail::Templates::FeedbackEmail)
#=> 'constant'

## FeedbackEmail requires email_address
begin
  Onetime::Mail::Templates::FeedbackEmail.new({
    message: @feedback_message,
    display_domain: @feedback_domain
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## FeedbackEmail requires message
begin
  Onetime::Mail::Templates::FeedbackEmail.new({
    email_address: @feedback_email,
    display_domain: @feedback_domain
  })
rescue ArgumentError => e
  e.message
end
#=> 'Message required'

## FeedbackEmail requires display_domain
begin
  Onetime::Mail::Templates::FeedbackEmail.new({
    email_address: @feedback_email,
    message: @feedback_message
  })
rescue ArgumentError => e
  e.message
end
#=> 'Display domain required'

## FeedbackEmail initializes with valid data
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.class
#=> Onetime::Mail::Templates::FeedbackEmail

## FeedbackEmail subject includes date and domain
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.subject.include?(@feedback_domain)
#=> true

## FeedbackEmail subject includes domain strategy
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain,
  domain_strategy: 'custom'
})
template.subject.include?('custom')
#=> true

## FeedbackEmail subject defaults strategy to 'default'
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.subject.include?('default')
#=> true

## FeedbackEmail recipient_email returns email_address
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.recipient_email
#=> @feedback_email

## FeedbackEmail render_text returns string with message
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.render_text.include?('test feedback message')
#=> true

## FeedbackEmail render_html returns string with message
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.render_html.include?('test feedback message')
#=> true

## FeedbackEmail render_text includes email address
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.render_text.include?(@feedback_email)
#=> true

## FeedbackEmail render_text includes domain
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.render_text.include?(@feedback_domain)
#=> true

## Mailer.deliver with :feedback_email works
Onetime::Mail::Mailer.reset!
result = Onetime::Mail.deliver(:feedback_email, {
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
result[:status]
#=> 'logged'

## Mailer.deliver with :feedback_email returns correct recipient
Onetime::Mail::Mailer.reset!
result = Onetime::Mail.deliver(:feedback_email, {
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
result[:to]
#=> @feedback_email

## FeedbackEmail to_email builds correct hash
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
email = template.to_email(from: 'noreply@example.com')
email[:to]
#=> @feedback_email

## FeedbackEmail to_email includes subject
template = Onetime::Mail::Templates::FeedbackEmail.new({
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
email = template.to_email(from: 'noreply@example.com')
email[:subject].include?('Feedback')
#=> true
