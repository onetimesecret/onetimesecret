# frozen_string_literal: true

# These tryouts test the email template functionality in the OneTime application,
# specifically for secret link emails with and without share_domain.
# They cover:
#
# 1. Creating email views for SecretLink with and without share_domain
# 2. Rendering email templates with different locales and share_domain values
# 3. Verifying email subject lines and content
#
# These tests ensure that email templates are correctly generated and localized,
# and that the share_domain feature is properly handled in the email content.

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test.yaml')
OT.boot!

@email = 'tryouts+40@onetimesecret.com'
@cust = OT::Customer.create @email
@secret = OT::Secret.create
@locale = 'en'
@recipient = 'tryouts+recipient@onetimesecret.com'

## Can create a view for SecretLink without share_domain
view = OT::App::Mail::SecretLink.new @cust, @locale, @secret, @recipient
[view.uri_path, view[:secret].identifier, view[:email_address]]
#=> ["/secret/#{@secret.identifier}", @secret.identifier, @recipient]

## Renders correct subject for SecretLink without share_domain (English)
view = OT::App::Mail::SecretLink.new @cust, 'en', @secret, @recipient
view.subject
#=> "#{@email} sent you a secret"

## Renders correct subject for SecretLink without share_domain (Spanish)
view = OT::App::Mail::SecretLink.new @cust, 'es', @secret, @recipient
view.subject
#=> "#{@email} le ha enviado un secreto"

## Can create a view for SecretLink with share_domain
@secret.share_domain = 'example.com'
@secret.save
view = OT::App::Mail::SecretLink.new @cust, @locale, @secret, @recipient
[view.uri_path, view[:secret].identifier, view[:email_address], view[:secret].share_domain]
#=> ["/secret/#{@secret.identifier}", @secret.identifier, @recipient, 'example.com']

## Renders correct subject for SecretLink with share_domain (English)
view = OT::App::Mail::SecretLink.new @cust, 'en', @secret, @recipient
view.subject
#=> "#{@email} sent you a secret"

## Renders correct subject for SecretLink with share_domain (Spanish)
view = OT::App::Mail::SecretLink.new @cust, 'es', @secret, @recipient
view.subject
#=> "#{@email} le ha enviado un secreto"

## Includes share_domain in email body (English)
view = OT::App::Mail::SecretLink.new @cust, 'en', @secret, @recipient
view.render.include?("https://example.com/secret/#{@secret.key}")
#=> true

## Includes share_domain in email body (Spanish)
view = OT::App::Mail::SecretLink.new @cust, 'es', @secret, @recipient
view.render.include?("https://example.com/secret/#{@secret.key}")
#=> true

# Teardown
@secret.destroy!
@cust.destroy!
