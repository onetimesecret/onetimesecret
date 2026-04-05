# try/unit/mail/templates_payment_failed_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::PaymentFailed class.
#
# PaymentFailed is sent when a payment attempt fails.
# Required data: email_address, amount, currency, plan_name, failure_reason
# Optional: retry_date, update_payment_url
#
# NOTE: These tests require billing to be enabled (etc/billing.yaml with enabled: true)

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Check if billing is enabled - tests require it
BILLING_ENABLED = OT.billing_config.enabled?

unless BILLING_ENABLED
  puts 'SKIP: Billing mail template tests require billing to be enabled'
end

# Load the mail module (only when billing enabled)
if BILLING_ENABLED
  require 'onetime/mail'
  require 'onetime/mail/views/payment_failed'

  @valid_data = {
    email_address: 'customer@example.com',
    amount: 1999,
    currency: 'cad',
    plan_name: 'Pro Plan',
    failure_reason: 'Card declined'
  }
end

# TRYOUTS

## PaymentFailed validates presence of email_address
if BILLING_ENABLED
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
end
#=> BILLING_ENABLED ? 'Email address required' : nil

## PaymentFailed validates presence of amount
if BILLING_ENABLED
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
end
#=> BILLING_ENABLED ? 'Amount required' : nil

## PaymentFailed validates presence of currency
if BILLING_ENABLED
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
end
#=> BILLING_ENABLED ? 'Currency required' : nil

## PaymentFailed validates presence of plan_name
if BILLING_ENABLED
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
end
#=> BILLING_ENABLED ? 'Plan name required' : nil

## PaymentFailed validates presence of failure_reason
if BILLING_ENABLED
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
end
#=> BILLING_ENABLED ? 'Failure reason required' : nil

## PaymentFailed accepts valid data without error
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
  template.class
end
#=> BILLING_ENABLED ? Onetime::Mail::Templates::PaymentFailed : nil

## PaymentFailed recipient_email returns email_address from data
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
  template.recipient_email
end
#=> BILLING_ENABLED ? 'customer@example.com' : nil

## PaymentFailed formatted_amount converts cents to dollars with CAD symbol
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
  template.formatted_amount
end
#=> BILLING_ENABLED ? 'CA$19.99' : nil

## PaymentFailed failure_reason returns data value
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
  template.failure_reason
end
#=> BILLING_ENABLED ? 'Card declined' : nil

## PaymentFailed retry_date_formatted returns human-readable date when provided
if BILLING_ENABLED
  data = @valid_data.merge(retry_date: '2024-01-18T10:30:00Z')
  template = Onetime::Mail::Templates::PaymentFailed.new(data)
  template.retry_date_formatted
end
#=> BILLING_ENABLED ? 'January 18, 2024' : nil

## PaymentFailed retry_date_formatted returns nil when not provided
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
  template.retry_date_formatted
end
#=> nil

## PaymentFailed update_payment_url returns data value when provided
if BILLING_ENABLED
  data = @valid_data.merge(update_payment_url: 'https://example.com/billing')
  template = Onetime::Mail::Templates::PaymentFailed.new(data)
  template.update_payment_url
end
#=> BILLING_ENABLED ? 'https://example.com/billing' : nil

## PaymentFailed update_payment_url returns nil when not provided
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
  template.update_payment_url
end
#=> nil

## PaymentFailed subject method is defined
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentFailed.new(@valid_data)
  template.respond_to?(:subject)
end
#=> BILLING_ENABLED ? true : nil
