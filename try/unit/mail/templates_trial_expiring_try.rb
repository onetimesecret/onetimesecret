# try/unit/mail/templates_trial_expiring_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::TrialExpiring class.
#
# TrialExpiring is sent when a customer's trial period is about to end.
# Required data: email_address, plan_name, trial_ends_at, days_remaining
# Optional: upgrade_url
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
  require 'onetime/mail/views/trial_expiring'

  @valid_data = {
    email_address: 'customer@example.com',
    plan_name: 'Pro Plan',
    trial_ends_at: '2024-01-20T23:59:59Z',
    days_remaining: 5
  }
end

# TRYOUTS

## TrialExpiring validates presence of email_address
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::TrialExpiring.new({
      plan_name: 'Pro Plan',
      trial_ends_at: '2024-01-20T23:59:59Z',
      days_remaining: 5
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Email address required' : nil

## TrialExpiring validates presence of plan_name
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::TrialExpiring.new({
      email_address: 'customer@example.com',
      trial_ends_at: '2024-01-20T23:59:59Z',
      days_remaining: 5
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Plan name required' : nil

## TrialExpiring validates presence of trial_ends_at
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::TrialExpiring.new({
      email_address: 'customer@example.com',
      plan_name: 'Pro Plan',
      days_remaining: 5
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Trial ends at required' : nil

## TrialExpiring validates presence of days_remaining
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::TrialExpiring.new({
      email_address: 'customer@example.com',
      plan_name: 'Pro Plan',
      trial_ends_at: '2024-01-20T23:59:59Z'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Days remaining required' : nil

## TrialExpiring accepts valid data without error
if BILLING_ENABLED
  template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
  template.class
end
#=> BILLING_ENABLED ? Onetime::Mail::Templates::TrialExpiring : nil

## TrialExpiring recipient_email returns email_address from data
if BILLING_ENABLED
  template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
  template.recipient_email
end
#=> BILLING_ENABLED ? 'customer@example.com' : nil

## TrialExpiring plan_name returns data value
if BILLING_ENABLED
  template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
  template.plan_name
end
#=> BILLING_ENABLED ? 'Pro Plan' : nil

## TrialExpiring days_remaining returns integer value
if BILLING_ENABLED
  template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
  template.days_remaining
end
#=> BILLING_ENABLED ? 5 : nil

## TrialExpiring days_remaining converts string to integer
if BILLING_ENABLED
  data = @valid_data.merge(days_remaining: '7')
  template = Onetime::Mail::Templates::TrialExpiring.new(data)
  template.days_remaining
end
#=> BILLING_ENABLED ? 7 : nil

## TrialExpiring trial_ends_at_formatted returns human-readable date
if BILLING_ENABLED
  template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
  template.trial_ends_at_formatted
end
#=> BILLING_ENABLED ? 'January 20, 2024' : nil

## TrialExpiring upgrade_url returns data value when provided
if BILLING_ENABLED
  data = @valid_data.merge(upgrade_url: 'https://example.com/upgrade')
  template = Onetime::Mail::Templates::TrialExpiring.new(data)
  template.upgrade_url
end
#=> BILLING_ENABLED ? 'https://example.com/upgrade' : nil

## TrialExpiring upgrade_url returns nil when not provided
if BILLING_ENABLED
  template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
  template.upgrade_url
end
#=> nil

## TrialExpiring urgent? returns false when days_remaining > 3
if BILLING_ENABLED
  template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
  template.urgent?
end
#=> BILLING_ENABLED ? false : nil

## TrialExpiring urgent? returns true when days_remaining <= 3
if BILLING_ENABLED
  data = @valid_data.merge(days_remaining: 3)
  template = Onetime::Mail::Templates::TrialExpiring.new(data)
  template.urgent?
end
#=> BILLING_ENABLED ? true : nil

## TrialExpiring last_day? returns false when days_remaining > 1
if BILLING_ENABLED
  template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
  template.last_day?
end
#=> BILLING_ENABLED ? false : nil

## TrialExpiring last_day? returns true when days_remaining <= 1
if BILLING_ENABLED
  data = @valid_data.merge(days_remaining: 1)
  template = Onetime::Mail::Templates::TrialExpiring.new(data)
  template.last_day?
end
#=> BILLING_ENABLED ? true : nil

## TrialExpiring subject method is defined
if BILLING_ENABLED
  template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
  template.respond_to?(:subject)
end
#=> BILLING_ENABLED ? true : nil
