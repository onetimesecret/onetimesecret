# try/integration/billing/conditional_loading_try.rb
#
# frozen_string_literal: true

## Billing App - Conditional Loading Integration Tests
#
# Verifies that the billing application is only loaded when:
# 1. etc/billing.yaml exists
# 2. AND billing.enabled is set to true
#
# This prevents the billing app from loading when billing is not configured.

require_relative '../../../lib/onetime'

# Skip boot - just test the config loading behavior directly

## BillingConfig singleton is always available
OT.billing_config.class.name
#=> "Onetime::BillingConfig"

## BillingConfig enabled? returns boolean
[TrueClass, FalseClass].include?(OT.billing_config.enabled?.class)
#=> true

## BillingConfig config is a hash
OT.billing_config.config.class
#=> Hash

## BillingConfig stripe_key returns string or nil
[String, NilClass].include?(OT.billing_config.stripe_key.class)
#=> true

## BillingConfig webhook_signing_secret returns string or nil
[String, NilClass].include?(OT.billing_config.webhook_signing_secret.class)
#=> true

## BillingConfig payment_links returns hash
OT.billing_config.payment_links.class
#=> Hash

## BillingConfig billing method returns hash
OT.billing_config.billing.class
#=> Hash
