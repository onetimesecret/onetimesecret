# frozen_string_literal: true

require_relative '../../../lib/onetime'

## Can load BillingConfig when file doesn't exist
config = Onetime::BillingConfig.instance
config.config
#=> {}

## enabled? returns false when file doesn't exist
config = Onetime::BillingConfig.instance
config.enabled?
#=> false

## stripe_key returns nil when file doesn't exist
config = Onetime::BillingConfig.instance
config.stripe_key
#=> nil

## webhook_signing_secret returns nil when file doesn't exist
config = Onetime::BillingConfig.instance
config.webhook_signing_secret
#=> nil

## payment_links returns empty hash when file doesn't exist
config = Onetime::BillingConfig.instance
config.payment_links
#=> {}
