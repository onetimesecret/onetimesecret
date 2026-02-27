# try/unit/mail/templates_payment_receipt_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::PaymentReceipt class.
#
# PaymentReceipt is sent after successful payment processing.
# Required data: email_address, amount, currency, plan_name, invoice_id, paid_at
# Optional: invoice_url

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
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

# TRYOUTS

## PaymentReceipt validates presence of email_address
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
#=> 'Email address required'

## PaymentReceipt validates presence of amount
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
#=> 'Amount required'

## PaymentReceipt validates presence of currency
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
#=> 'Currency required'

## PaymentReceipt validates presence of plan_name
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
#=> 'Plan name required'

## PaymentReceipt validates presence of invoice_id
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
#=> 'Invoice ID required'

## PaymentReceipt validates presence of paid_at
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
#=> 'Paid at required'

## PaymentReceipt accepts valid data without error
template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::PaymentReceipt

## PaymentReceipt recipient_email returns email_address from data
template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
template.recipient_email
#=> 'customer@example.com'

## PaymentReceipt formatted_amount converts cents to dollars with USD symbol
template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
template.formatted_amount
#=> '$19.99'

## PaymentReceipt formatted_amount handles EUR currency
data = @valid_data.merge(currency: 'eur')
template = Onetime::Mail::Templates::PaymentReceipt.new(data)
template.formatted_amount.start_with?('€')
#=> true

## PaymentReceipt formatted_amount handles GBP currency
data = @valid_data.merge(currency: 'gbp')
template = Onetime::Mail::Templates::PaymentReceipt.new(data)
template.formatted_amount.start_with?('£')
#=> true

## PaymentReceipt paid_at_formatted returns human-readable date
template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
template.paid_at_formatted
#=> 'January 15, 2024'

## PaymentReceipt invoice_url returns data value when provided
data = @valid_data.merge(invoice_url: 'https://pay.stripe.com/invoice/abc')
template = Onetime::Mail::Templates::PaymentReceipt.new(data)
template.invoice_url
#=> 'https://pay.stripe.com/invoice/abc'

## PaymentReceipt invoice_url returns nil when not provided
template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
template.invoice_url
#=> nil

## PaymentReceipt subject method is defined
template = Onetime::Mail::Templates::PaymentReceipt.new(@valid_data)
template.respond_to?(:subject)
#=> true
