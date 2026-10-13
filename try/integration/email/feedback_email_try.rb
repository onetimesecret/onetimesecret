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
@recipient_email = 'colonel@example.com'
@feedback_email = 'feedback-user@example.com'
@feedback_message = "This is a test feedback message.\nIt has multiple lines.\nThanks for the service!"
@feedback_domain = 'custom.onetimesecret.com'

# TRYOUTS

## FeedbackEmail template class exists
defined?(Onetime::Mail::Templates::FeedbackEmail)
#=> 'constant'

## FeedbackEmail requires recipient_email
begin
  Onetime::Mail::Templates::FeedbackEmail.new({
    email_address: @feedback_email,
    message: @feedback_message,
    display_domain: @feedback_domain
  })
rescue ArgumentError => e
  e.message
end
#=> 'Recipient email required'

## FeedbackEmail requires email_address (sender)
begin
  Onetime::Mail::Templates::FeedbackEmail.new({
    recipient_email: @recipient_email,
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
    recipient_email: @recipient_email,
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
    recipient_email: @recipient_email,
    email_address: @feedback_email,
    message: @feedback_message
  })
rescue ArgumentError => e
  e.message
end
#=> 'Display domain required'

## FeedbackEmail initializes with valid data
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.class
#=> Onetime::Mail::Templates::FeedbackEmail

## FeedbackEmail subject includes date and domain
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.subject.include?(@feedback_domain)
#=> true

## FeedbackEmail subject includes domain strategy
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain,
  domain_strategy: 'custom'
})
template.subject.include?('custom')
#=> true

## FeedbackEmail subject defaults strategy to 'default'
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.subject.include?('default')
#=> true

## FeedbackEmail recipient_email returns the colonel email (not sender)
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.recipient_email
#=> @recipient_email

## FeedbackEmail sender_email returns the feedback submitter email
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.sender_email
#=> @feedback_email

## FeedbackEmail render_text returns string with message
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.render_text.include?('test feedback message')
#=> true

## FeedbackEmail render_html returns string with message
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.render_html.include?('test feedback message')
#=> true

## FeedbackEmail render_text includes sender email address
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.render_text.include?(@feedback_email)
#=> true

## FeedbackEmail render_text includes domain
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
template.render_text.include?(@feedback_domain)
#=> true

## Mailer.deliver with :feedback_email works
Onetime::Mail::Mailer.reset!
result = Onetime::Mail.deliver(:feedback_email, {
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
result.response[:status]
#=> 'logged'

## Mailer.deliver with :feedback_email returns correct recipient (colonel)
Onetime::Mail::Mailer.reset!
result = Onetime::Mail.deliver(:feedback_email, {
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
result.response[:to]
#=> @recipient_email

## FeedbackEmail to_email builds correct hash with colonel as recipient
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
email = template.to_email(from: 'noreply@example.com')
email[:to]
#=> @recipient_email

## FeedbackEmail to_email includes subject
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain
})
email = template.to_email(from: 'noreply@example.com')
email[:subject].include?('Feedback')
#=> true

## render_text links the submitter and each organization to its colonel page
@linked = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain,
  user_id: 'urfeedback1',
  customer_extid: 'urfeedback1',
  organization_extids: %w[onfeedback1 onfeedback2],
})

@base = @linked.send(:site_baseuri)
@text = @linked.render_text
[
  @text.include?("#{@base}/colonel/customers/urfeedback1"),
  @text.include?("onfeedback1  #{@base}/colonel/organizations/onfeedback1"),
  @text.include?("onfeedback2  #{@base}/colonel/organizations/onfeedback2"),
]
#=> [true, true, true]

## render_html links the same colonel pages
@html = @linked.render_html
[
  @html.include?(%(href="#{@base}/colonel/customers/urfeedback1")),
  @html.include?(%(href="#{@base}/colonel/organizations/onfeedback1")),
  @html.include?(%(href="#{@base}/colonel/organizations/onfeedback2")),
]
#=> [true, true, true]

## colonel links go to the canonical site host, not the feedback's custom domain
@text.include?("#{@feedback_domain}/colonel/")
#=> false

## anonymous feedback carries no colonel links
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: 'anonymous',
  message: @feedback_message,
  display_domain: @feedback_domain,
  user_id: 'anon:abcd1234',
})
[template.render_text.include?('/colonel/'), template.render_html.include?('/colonel/')]
#=> [false, false]

## string-keyed ids (as deserialized from the email job queue) render too
template = Onetime::Mail::Templates::FeedbackEmail.new({
  recipient_email: @recipient_email,
  email_address: @feedback_email,
  message: @feedback_message,
  display_domain: @feedback_domain,
  'customer_extid' => 'urfeedback2',
  'organization_extids' => ['onfeedback3'],
})
[template.colonel_customer_url, template.organizations.map { |org| org[:extid] }]
#=> ["#{@base}/colonel/customers/urfeedback2", ['onfeedback3']]
