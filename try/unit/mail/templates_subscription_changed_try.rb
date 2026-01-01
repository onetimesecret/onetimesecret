# try/unit/mail/templates_subscription_changed_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::SubscriptionChanged class.
#
# SubscriptionChanged is sent when a customer's subscription plan changes.
# Required data: email_address, old_plan, new_plan, effective_date
# Optional: is_upgrade

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'
require 'onetime/mail/templates/subscription_changed'

@valid_data = {
  email_address: 'customer@example.com',
  old_plan: 'Basic Plan',
  new_plan: 'Pro Plan',
  effective_date: '2024-01-15T00:00:00Z'
}

# TRYOUTS

## SubscriptionChanged validates presence of email_address
begin
  Onetime::Mail::Templates::SubscriptionChanged.new({
    old_plan: 'Basic Plan',
    new_plan: 'Pro Plan',
    effective_date: '2024-01-15T00:00:00Z'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Email address required'

## SubscriptionChanged validates presence of old_plan
begin
  Onetime::Mail::Templates::SubscriptionChanged.new({
    email_address: 'customer@example.com',
    new_plan: 'Pro Plan',
    effective_date: '2024-01-15T00:00:00Z'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Old plan required'

## SubscriptionChanged validates presence of new_plan
begin
  Onetime::Mail::Templates::SubscriptionChanged.new({
    email_address: 'customer@example.com',
    old_plan: 'Basic Plan',
    effective_date: '2024-01-15T00:00:00Z'
  })
rescue ArgumentError => e
  e.message
end
#=> 'New plan required'

## SubscriptionChanged validates presence of effective_date
begin
  Onetime::Mail::Templates::SubscriptionChanged.new({
    email_address: 'customer@example.com',
    old_plan: 'Basic Plan',
    new_plan: 'Pro Plan'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Effective date required'

## SubscriptionChanged accepts valid data without error
template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::SubscriptionChanged

## SubscriptionChanged recipient_email returns email_address from data
template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
template.recipient_email
#=> 'customer@example.com'

## SubscriptionChanged old_plan returns data value
template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
template.old_plan
#=> 'Basic Plan'

## SubscriptionChanged new_plan returns data value
template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
template.new_plan
#=> 'Pro Plan'

## SubscriptionChanged effective_date_formatted returns human-readable date
template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
template.effective_date_formatted
#=> 'January 15, 2024'

## SubscriptionChanged upgrade? returns true when is_upgrade is true
data = @valid_data.merge(is_upgrade: true)
template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
template.upgrade?
#=> true

## SubscriptionChanged upgrade? returns false when is_upgrade is false
data = @valid_data.merge(is_upgrade: false)
template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
template.upgrade?
#=> false

## SubscriptionChanged upgrade? returns false when is_upgrade not provided
template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
template.upgrade?
#=> false

## SubscriptionChanged downgrade? returns true when is_upgrade is false
data = @valid_data.merge(is_upgrade: false)
template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
template.downgrade?
#=> true

## SubscriptionChanged downgrade? returns false when is_upgrade is true
data = @valid_data.merge(is_upgrade: true)
template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
template.downgrade?
#=> false

## SubscriptionChanged downgrade? returns false when is_upgrade not provided
template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
template.downgrade?
#=> false

## SubscriptionChanged change_type returns upgrade when is_upgrade is true
data = @valid_data.merge(is_upgrade: true)
template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
template.change_type
#=> 'upgrade'

## SubscriptionChanged change_type returns downgrade when is_upgrade is false
data = @valid_data.merge(is_upgrade: false)
template = Onetime::Mail::Templates::SubscriptionChanged.new(data)
template.change_type
#=> 'downgrade'

## SubscriptionChanged change_type returns change when is_upgrade not provided
template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
template.change_type
#=> 'change'

## SubscriptionChanged subject method is defined
template = Onetime::Mail::Templates::SubscriptionChanged.new(@valid_data)
template.respond_to?(:subject)
#=> true
