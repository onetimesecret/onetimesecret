# try/unit/mail/configuration_error_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::ConfigurationError, raised when the install's
# delivery backend cannot be built from its configuration.
#
# A missing SMTP host or missing provider credentials describes the install,
# not the message. EmailWorker reads ArgumentError as a malformed message and
# dead-letters it, so the backends must not raise ArgumentError for this.
#
# Covers:
# - ConfigurationError is neither an ArgumentError nor a DeliveryError
# - every backend's validate_config! raises it with the provider name
# - Mailer.validate_delivery_config! raises it for a missing SMTP host and
#   does not memoize a backend

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'onetime/mail'

# Swap Mailer.emailer_config for one block, then put the original back, so
# later tryout files in the same process see the state they expect.
@emailer_config_private = Onetime::Mail::Mailer.singleton_class.private_method_defined?(:emailer_config)
@with_emailer_config    = ->(conf, &blk) do
  mailer      = Onetime::Mail::Mailer
  original    = mailer.singleton_class.instance_method(:emailer_config)
  was_private = mailer.singleton_class.private_method_defined?(:emailer_config)
  saved_host  = ENV.delete('SMTP_HOST')
  mailer.singleton_class.send(:define_method, :emailer_config) { conf }
  mailer.reset!
  blk.call
ensure
  mailer.singleton_class.send(:define_method, :emailer_config, original)
  mailer.singleton_class.send(:private, :emailer_config) if was_private
  ENV['SMTP_HOST'] = saved_host if saved_host
  mailer.reset!
end

# Build a backend and return the ConfigurationError it raises, or nil.
@config_error_from = ->(klass, config) do
  saved = %w[SMTP_HOST AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY SENDGRID_API_KEY
             LETTERMINT_API_TOKEN SMTP2GO_API_KEY].to_h { |key| [key, ENV.delete(key)] }
  klass.new(config)
  nil
rescue Onetime::Mail::ConfigurationError => ex
  ex
ensure
  saved.each { |key, value| ENV[key] = value if value }
end

# TRYOUTS

## ConfigurationError is a StandardError
Onetime::Mail::ConfigurationError <= StandardError
#=> true

## ConfigurationError is not an ArgumentError, which the worker reads as a malformed message
(Onetime::Mail::ConfigurationError <= ArgumentError) == true
#=> false

## ConfigurationError is not a DeliveryError, which is a provider's answer to one message
(Onetime::Mail::ConfigurationError <= Onetime::Mail::DeliveryError) == true
#=> false

## ConfigurationError names the provider
ex = Onetime::Mail::ConfigurationError.new('SMTP host must be configured', provider: 'smtp')
[ex.message, ex.provider]
#=> ['SMTP host must be configured', 'smtp']

## SMTP without a host raises ConfigurationError naming smtp
ex = @config_error_from.call(Onetime::Mail::Delivery::SMTP, {})
[ex.class, ex.provider, ex.message]
#=> [Onetime::Mail::ConfigurationError, 'smtp', 'SMTP host must be configured']

## SES without credentials raises ConfigurationError naming ses
ex = @config_error_from.call(Onetime::Mail::Delivery::SES, { 'region' => 'us-east-1' })
[ex.class, ex.provider]
#=> [Onetime::Mail::ConfigurationError, 'ses']

## SendGrid without an API key raises ConfigurationError naming sendgrid
ex = @config_error_from.call(Onetime::Mail::Delivery::SendGrid, {})
[ex.class, ex.provider]
#=> [Onetime::Mail::ConfigurationError, 'sendgrid']

## Lettermint without an API token raises ConfigurationError naming lettermint
ex = @config_error_from.call(Onetime::Mail::Delivery::Lettermint, {})
[ex.class, ex.provider]
#=> [Onetime::Mail::ConfigurationError, 'lettermint']

## SMTP2GO without an API key raises ConfigurationError naming smtp2go
ex = @config_error_from.call(Onetime::Mail::Delivery::Smtp2go, {})
[ex.class, ex.provider]
#=> [Onetime::Mail::ConfigurationError, 'smtp2go']

## SMTP with a host builds
@config_error_from.call(Onetime::Mail::Delivery::SMTP, { 'host' => 'smtp.example.com' })
#=> nil

## Mailer.validate_delivery_config! raises ConfigurationError for mode smtp with a blank host
result = nil
@with_emailer_config.call({ 'mode' => 'smtp', 'host' => '' }) do
  Onetime::Mail::Mailer.validate_delivery_config!
rescue Onetime::Mail::ConfigurationError => ex
  result = [ex.class, ex.provider]
end
result
#=> [Onetime::Mail::ConfigurationError, 'smtp']

## Mailer.validate_delivery_config! returns the provider and keeps no backend
result = nil
@with_emailer_config.call({ 'mode' => 'smtp', 'host' => 'smtp.example.com' }) do
  result = [
    Onetime::Mail::Mailer.validate_delivery_config!,
    Onetime::Mail::Mailer.instance_variable_get(:@delivery_backend),
  ]
end
result
#=> ['smtp', nil]

## The mailer's emailer_config keeps its visibility after the swap
Onetime::Mail::Mailer.singleton_class.private_method_defined?(:emailer_config) == @emailer_config_private
#=> true
