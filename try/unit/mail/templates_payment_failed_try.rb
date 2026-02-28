# try/unit/mail/templates_payment_failed_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::PaymentFailed class.
#
# PaymentFailed is sent when a payment attempt fails.
# Required data: email_address, amount, currency, plan_name, failure_reason
# Optional: retry_date, update_payment_url

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/views/payment_failed'

@valid_data = {
  email_address: 'customer@example.com',
  amount: 1999,
  currency: 'cad',
  plan_name: 'Pro Plan',
  failure_reason: 'Card declined'
}

# TRYOUTS

## PaymentFailed validates presence of email_address
begin
  Onetime::Mail::Templates::PaymentFailed.new({
    amount: 1999,
    currency: 'cad',
    plan_name: 'Pro Plan',
    failure_reason: 'Card declined'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## PaymentFailed validates presence of amount
begin
  Onetime::Mail::Templates::PaymentFailed.new({
    email_address: 'customer@example.com',
    currency: 'cad',
    plan_name: 'Pro Plan',
    failure_reason: 'Card declined'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Amount required'

## PaymentFailed validates presence of currency
begin
  Onetime::Mail::Templates::PaymentFailed.new({
    email_address: 'customer@example.com',
    amount: 1999,
    plan_name: 'Pro Plan',
    failure_reason: 'Card declined'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Currency required'

## PaymentFailed validates presence of plan_name
begin
  Onetime::Mail::Templates::PaymentFailed.new({
    email_address: 'customer@example.com',
    amount: 1999,
    currency: 'cad',
    failure_reason: 'Card declined'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Plan name required'

## PaymentFailed validates presence of failure_reason
begin
  Onetime::Mail::Templates::PaymentFailed.new({
    email_address: 'customer@example.com',
    amount: 1999,
    currency: 'cad',
    plan_name: 'Pro Plan'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Failure reason required'

## PaymentFailed accepts valid data without error
template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::PaymentFailed

## PaymentFailed recipient_email returns email_address from data
template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
template.recipient_email
#=> 'customer@example.com'

## PaymentFailed formatted_amount converts cents to dollars with CAD symbol
template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
template.formatted_amount
#=> 'CA$19.99'

## PaymentFailed failure_reason returns data value
template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
template.failure_reason
#=> 'Card declined'

## PaymentFailed retry_date_formatted returns human-readable date when provided
data = @valid_data.merge(retry_date: '2024-01-18T10:30:00Z')
template = Onetime::Mail::Templates::PaymentFailed.new(data)
template.retry_date_formatted
#=> 'January 18, 2024'

## PaymentFailed retry_date_formatted returns nil when not provided
template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
template.retry_date_formatted
#=> nil

## PaymentFailed update_payment_url returns data value when provided
data = @valid_data.merge(update_payment_url: 'https://example.com/billing')
template = Onetime::Mail::Templates::PaymentFailed.new(data)
template.update_payment_url
#=> 'https://example.com/billing'

## PaymentFailed update_payment_url returns nil when not provided
template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
template.update_payment_url
#=> nil

## PaymentFailed subject method is defined
template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
template.respond_to?(:subject)
#=> true
