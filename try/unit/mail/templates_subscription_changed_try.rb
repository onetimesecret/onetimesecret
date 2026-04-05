# try/unit/mail/templates_subscription_changed_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::SubscriptionChanged class.
#
# SubscriptionChanged is sent when a customer's subscription plan changes.
# Required data: email_address, old_plan, new_plan, effective_date
# Optional: is_upgrade
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
  require 'onetime/mail/views/subscription_changed'

  @valid_data = {
    email_address: 'customer@example.com',
    old_plan: 'Basic Plan',
    new_plan: 'Pro Plan',
    effective_date: '2024-01-15T00:00:00Z'
  }
end

# TRYOUTS

## SubscriptionChanged validates presence of email_address
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::SubscriptionChanged.new({
      old_plan: 'Basic Plan',
      new_plan: 'Pro Plan',
      effective_date: '2024-01-15T00:00:00Z'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Email address required' : nil

## SubscriptionChanged validates presence of old_plan
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::SubscriptionChanged.new({
      email_address: 'customer@example.com',
      new_plan: 'Pro Plan',
      effective_date: '2024-01-15T00:00:00Z'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Old plan required' : nil

## SubscriptionChanged validates presence of new_plan
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::SubscriptionChanged.new({
      email_address: 'customer@example.com',
      old_plan: 'Basic Plan',
      effective_date: '2024-01-15T00:00:00Z'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'New plan required' : nil

## SubscriptionChanged validates presence of effective_date
if BILLING_ENABLED
  begin
    Onetime::Mail::Templates::SubscriptionChanged.new({
      email_address: 'customer@example.com',
      old_plan: 'Basic Plan',
      new_plan: 'Pro Plan'
    })
  rescue ArgumentError => e
    e.message
  end
end
#=> BILLING_ENABLED ? 'Effective date required' : nil

## SubscriptionChanged accepts valid data without error
if BILLING_ENABLED
  template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
  template.class
end
#=> BILLING_ENABLED ? Onetime::Mail::Templates::SubscriptionChanged : nil

## SubscriptionChanged recipient_email returns email_address from data
if BILLING_ENABLED
  template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
  template.recipient_email
end
#=> BILLING_ENABLED ? 'customer@example.com' : nil

## SubscriptionChanged old_plan returns data value
if BILLING_ENABLED
  template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
  template.old_plan
end
#=> BILLING_ENABLED ? 'Basic Plan' : nil

## SubscriptionChanged new_plan returns data value
if BILLING_ENABLED
  template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
  template.new_plan
end
#=> BILLING_ENABLED ? 'Pro Plan' : nil

## SubscriptionChanged effective_date_formatted returns human-readable date
if BILLING_ENABLED
  template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
  template.effective_date_formatted
end
#=> BILLING_ENABLED ? 'January 15, 2024' : nil

## SubscriptionChanged upgrade? returns true when is_upgrade is true
if BILLING_ENABLED
  data = @valid_data.merge(is_upgrade: true)
  template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
  template.upgrade?
end
#=> BILLING_ENABLED ? true : nil

## SubscriptionChanged upgrade? returns false when is_upgrade is false
if BILLING_ENABLED
  data = @valid_data.merge(is_upgrade: false)
  template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
  template.upgrade?
end
#=> BILLING_ENABLED ? false : nil

## SubscriptionChanged upgrade? returns false when is_upgrade not provided
if BILLING_ENABLED
  template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
  template.upgrade?
end
#=> BILLING_ENABLED ? false : nil

## SubscriptionChanged downgrade? returns true when is_upgrade is false
if BILLING_ENABLED
  data = @valid_data.merge(is_upgrade: false)
  template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
  template.downgrade?
end
#=> BILLING_ENABLED ? true : nil

## SubscriptionChanged downgrade? returns false when is_upgrade is true
if BILLING_ENABLED
  data = @valid_data.merge(is_upgrade: true)
  template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
  template.downgrade?
end
#=> BILLING_ENABLED ? false : nil

## SubscriptionChanged downgrade? returns false when is_upgrade not provided
if BILLING_ENABLED
  template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
  template.downgrade?
end
#=> BILLING_ENABLED ? false : nil

## SubscriptionChanged change_type returns upgrade when is_upgrade is true
if BILLING_ENABLED
  data = @valid_data.merge(is_upgrade: true)
  template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
  template.change_type
end
#=> BILLING_ENABLED ? 'upgrade' : nil

## SubscriptionChanged change_type returns downgrade when is_upgrade is false
if BILLING_ENABLED
  data = @valid_data.merge(is_upgrade: false)
  template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
  template.change_type
end
#=> BILLING_ENABLED ? 'downgrade' : nil

## SubscriptionChanged change_type returns change when is_upgrade not provided
if BILLING_ENABLED
  template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
  template.change_type
end
#=> BILLING_ENABLED ? 'change' : nil

## SubscriptionChanged subject method is defined
if BILLING_ENABLED
  template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
  template.respond_to?(:subject)
end
#=> BILLING_ENABLED ? true : nil
