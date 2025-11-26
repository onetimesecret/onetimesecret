# try/integration/email/mailer_backend_selection_try.rb
#
# frozen_string_literal: true

# Tests the backend selection logic in Mailer.
#
# The Mailer selects backend based on:
# 1. Explicit mode in config (takes precedence)
# 2. Auto-detection based on config/env vars
# 3. Fallback to logger when nothing else matches
#
# Note: This test forces EMAILER_MODE to avoid using production backends.

require_relative '../../support/test_helpers'

# Force logger mode for safe testing
ENV['EMAILER_MODE'] = 'logger'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'

# Force config reload
Onetime::Config.load

# TRYOUTS

## Mailer has delivery_backend class method
Onetime::Mail::Mailer.respond_to?(:delivery_backend)
#=> true

## Mailer has reset! class method
Onetime::Mail::Mailer.respond_to?(:reset!)
#=> true

## Mailer has from_address class method
Onetime::Mail::Mailer.respond_to?(:from_address)
#=> true

## Mailer has from_name class method
Onetime::Mail::Mailer.respond_to?(:from_name)
#=> true

## With EMAILER_MODE=logger, backend is Logger
Onetime::Mail::Mailer.reset!
Onetime::Mail::Mailer.delivery_backend.class
#=> Onetime::Mail::Delivery::Logger

## Backend is cached after first access
Onetime::Mail::Mailer.reset!
backend1 = Onetime::Mail::Mailer.delivery_backend
backend2 = Onetime::Mail::Mailer.delivery_backend
backend1.object_id == backend2.object_id
#=> true

## reset! clears cached backend
Onetime::Mail::Mailer.reset!
backend1 = Onetime::Mail::Mailer.delivery_backend
Onetime::Mail::Mailer.reset!
backend2 = Onetime::Mail::Mailer.delivery_backend
backend1.object_id == backend2.object_id
#=> false

## from_address returns string
Onetime::Mail::Mailer.from_address.class
#=> String

## from_address is not empty
Onetime::Mail::Mailer.from_address.empty?
#=> false

## Unknown template raises ArgumentError
begin
  Onetime::Mail::Mailer.send(:template_class_for, :nonexistent)
rescue ArgumentError => e
  e.message
end
#=> 'Unknown template: nonexistent'

## template_class_for :secret_link returns SecretLink
Onetime::Mail::Mailer.send(:template_class_for, :secret_link)
#=> Onetime::Mail::Templates::SecretLink

## template_class_for :welcome returns Welcome
Onetime::Mail::Mailer.send(:template_class_for, :welcome)
#=> Onetime::Mail::Templates::Welcome

## template_class_for :password_request returns PasswordRequest
Onetime::Mail::Mailer.send(:template_class_for, :password_request)
#=> Onetime::Mail::Templates::PasswordRequest

## template_class_for :incoming_secret returns IncomingSecret
Onetime::Mail::Mailer.send(:template_class_for, :incoming_secret)
#=> Onetime::Mail::Templates::IncomingSecret

## build_provider_config for logger returns empty hash
config = Onetime::Mail::Mailer.send(:build_provider_config, 'logger')
config
#=> {}

## build_provider_config for smtp includes host key
config = Onetime::Mail::Mailer.send(:build_provider_config, 'smtp')
config.key?(:host)
#=> true

## build_provider_config for ses includes region key
config = Onetime::Mail::Mailer.send(:build_provider_config, 'ses')
config.key?(:region)
#=> true

## build_provider_config for sendgrid includes api_key key
config = Onetime::Mail::Mailer.send(:build_provider_config, 'sendgrid')
config.key?(:api_key)
#=> true
