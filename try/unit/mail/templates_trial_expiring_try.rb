# try/unit/mail/templates_trial_expiring_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::TrialExpiring class.
#
# TrialExpiring is sent when a customer's trial period is about to end.
# Required data: email_address, plan_name, trial_ends_at, days_remaining
# Optional: upgrade_url

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/templates/trial_expiring'

@valid_data = {
  email_address: 'customer@example.com',
  plan_name: 'Pro Plan',
  trial_ends_at: '2024-01-20T23:59:59Z',
  days_remaining: 5
}

# TRYOUTS

## TrialExpiring validates presence of email_address
begin
  Onetime::Mail::Templates::TrialExpiring.new({
    plan_name: 'Pro Plan',
    trial_ends_at: '2024-01-20T23:59:59Z',
    days_remaining: 5
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## TrialExpiring validates presence of plan_name
begin
  Onetime::Mail::Templates::TrialExpiring.new({
    email_address: 'customer@example.com',
    trial_ends_at: '2024-01-20T23:59:59Z',
    days_remaining: 5
  })
rescue ArgumentError => e
  e.message
end
#=> 'Plan name required'

## TrialExpiring validates presence of trial_ends_at
begin
  Onetime::Mail::Templates::TrialExpiring.new({
    email_address: 'customer@example.com',
    plan_name: 'Pro Plan',
    days_remaining: 5
  })
rescue ArgumentError => e
  e.message
end
#=> 'Trial ends at required'

## TrialExpiring validates presence of days_remaining
begin
  Onetime::Mail::Templates::TrialExpiring.new({
    email_address: 'customer@example.com',
    plan_name: 'Pro Plan',
    trial_ends_at: '2024-01-20T23:59:59Z'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Days remaining required'

## TrialExpiring accepts valid data without error
template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::TrialExpiring

## TrialExpiring recipient_email returns email_address from data
template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
template.recipient_email
#=> 'customer@example.com'

## TrialExpiring plan_name returns data value
template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
template.plan_name
#=> 'Pro Plan'

## TrialExpiring days_remaining returns integer value
template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
template.days_remaining
#=> 5

## TrialExpiring days_remaining converts string to integer
data = @valid_data.merge(days_remaining: '7')
template = Onetime::Mail::Templates::TrialExpiring.new(data)
template.days_remaining
#=> 7

## TrialExpiring trial_ends_at_formatted returns human-readable date
template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
template.trial_ends_at_formatted
#=> 'January 20, 2024'

## TrialExpiring upgrade_url returns data value when provided
data = @valid_data.merge(upgrade_url: 'https://example.com/upgrade')
template = Onetime::Mail::Templates::TrialExpiring.new(data)
template.upgrade_url
#=> 'https://example.com/upgrade'

## TrialExpiring upgrade_url returns nil when not provided
template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
template.upgrade_url
#=> nil

## TrialExpiring urgent? returns false when days_remaining > 3
template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
template.urgent?
#=> false

## TrialExpiring urgent? returns true when days_remaining <= 3
data = @valid_data.merge(days_remaining: 3)
template = Onetime::Mail::Templates::TrialExpiring.new(data)
template.urgent?
#=> true

## TrialExpiring last_day? returns false when days_remaining > 1
template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
template.last_day?
#=> false

## TrialExpiring last_day? returns true when days_remaining <= 1
data = @valid_data.merge(days_remaining: 1)
template = Onetime::Mail::Templates::TrialExpiring.new(data)
template.last_day?
#=> true

## TrialExpiring subject method is defined
template = Onetime::Mail::Templates::TrialExpiring.new(@valid_data)
template.respond_to?(:subject)
#=> true
