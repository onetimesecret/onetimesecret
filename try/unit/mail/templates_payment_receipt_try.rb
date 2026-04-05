# try/unit/mail/templates_payment_receipt_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::PaymentReceipt class.
#
# PaymentReceipt is sent after successful payment processing.
# Required data: email_address, amount, currency, plan_name, invoice_id, paid_at
# Optional: invoice_url
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
  require 'onetime/mail/views/payment_receipt'

  @valid_data = {
    email_address: 'customer@example.com',
    amount: 1999,
    currency: 'cad',
    plan_name: 'Pro Plan',
    invoice_id: 'inv_abc123',
    paid_at: '2024-01-15T10:30:00Z'
  }
end

# TRYOUTS

## PaymentReceipt validates presence of email_address
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::PaymentReceipt.new({
      amount: 1999,
      currency: 'cad',
      plan_name: 'Pro Plan',
      invoice_id: 'inv_abc123',
      paid_at: '2024-01-15T10:30:00Z'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Email address required' : nil

## PaymentReceipt validates presence of amount
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::PaymentReceipt.new({
      email_address: 'customer@example.com',
      currency: 'cad',
      plan_name: 'Pro Plan',
      invoice_id: 'inv_abc123',
      paid_at: '2024-01-15T10:30:00Z'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Amount required' : nil

## PaymentReceipt validates presence of currency
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::PaymentReceipt.new({
      email_address: 'customer@example.com',
      amount: 1999,
      plan_name: 'Pro Plan',
      invoice_id: 'inv_abc123',
      paid_at: '2024-01-15T10:30:00Z'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Currency required' : nil

## PaymentReceipt validates presence of plan_name
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::PaymentReceipt.new({
      email_address: 'customer@example.com',
      amount: 1999,
      currency: 'cad',
      invoice_id: 'inv_abc123',
      paid_at: '2024-01-15T10:30:00Z'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Plan name required' : nil

## PaymentReceipt validates presence of invoice_id
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::PaymentReceipt.new({
      email_address: 'customer@example.com',
      amount: 1999,
      currency: 'cad',
      plan_name: 'Pro Plan',
      paid_at: '2024-01-15T10:30:00Z'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Invoice ID required' : nil

## PaymentReceipt validates presence of paid_at
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::PaymentReceipt.new({
      email_address: 'customer@example.com',
      amount: 1999,
      currency: 'cad',
      plan_name: 'Pro Plan',
      invoice_id: 'inv_abc123'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Paid at required' : nil

## PaymentReceipt accepts valid data without error
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
  template.class
end
#=> BILLING_ENABLED ? Onetime::Mail::Templates::PaymentReceipt : nil

## PaymentReceipt recipient_email returns email_address from data
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
  template.recipient_email
end
#=> BILLING_ENABLED ? 'customer@example.com' : nil

## PaymentReceipt formatted_amount converts cents to dollars with CAD symbol
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
  template.formatted_amount
end
#=> BILLING_ENABLED ? 'CA$19.99' : nil

## PaymentReceipt formatted_amount handles EUR currency
if BILLING_ENABLED
  data = @valid_data.merge(currency: 'eur')
  template = Onetime::Mail::Templates::PaymentReceipt.new(data)
  template.formatted_amount.start_with?('€')
end
#=> BILLING_ENABLED ? true : nil

## PaymentReceipt formatted_amount handles GBP currency
if BILLING_ENABLED
  data = @valid_data.merge(currency: 'gbp')
  template = Onetime::Mail::Templates::PaymentReceipt.new(data)
  template.formatted_amount.start_with?('£')
end
#=> BILLING_ENABLED ? true : nil

## PaymentReceipt paid_at_formatted returns human-readable date
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
  template.paid_at_formatted
end
#=> BILLING_ENABLED ? 'January 15, 2024' : nil

## PaymentReceipt invoice_url returns data value when provided
if BILLING_ENABLED
  data = @valid_data.merge(invoice_url: 'https://pay.stripe.com/invoice/abc')
  template = Onetime::Mail::Templates::PaymentReceipt.new(data)
  template.invoice_url
end
#=> BILLING_ENABLED ? 'https://pay.stripe.com/invoice/abc' : nil

## PaymentReceipt invoice_url returns nil when not provided
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
  template.invoice_url
end
#=> nil

## PaymentReceipt subject method is defined
if BILLING_ENABLED
  template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
  template.respond_to?(:subject)
end
#=> BILLING_ENABLED ? true : nil
