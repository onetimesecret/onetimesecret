# tests/unit/ruby/try/40_email_template_try.rb

# These tryouts test the email template functionality in the Onetime application,
# specifically for secret link emails with and without share_domain.
# They cover:
#
# 1. Creating email views for SecretLink with and without share_domain
# 2. Rendering email templates with different locales and share_domain values
# 3. Verifying email subject lines and content
#
# These tests ensure that email templates are correctly generated and localized,
# and that the share_domain feature is properly handled in the email content.

require_relative 'test_models'
# Use the default config file for tests
OT.boot! :test, false

@email = "tryouts+40+#{Time.now.to_i}@onetimesecret.com"
@cust = V1::Customer.create @email
@secret = V1::Secret.create
@locale = 'en'
@recipient = 'tryouts+recipient@onetimesecret.com'

## Can create a view for SecretLink without share_domain
view = OT::Mail::SecretLink.new @cust, @locale, @secret, @recipient
[view.uri_path, view[:secret].identifier, view[:email_address]]
#=> ["/secret/#{@secret.identifier}", @secret.identifier, @recipient]

## Renders correct subject for SecretLink without share_domain (English)
view = OT::Mail::SecretLink.new @cust, 'en', @secret, @recipient
view.subject
#=> "#{@email} sent you a secret"

## Renders correct subject for SecretLink without share_domain (French Canadian)
view = OT::Mail::SecretLink.new @cust, 'fr_CA', @secret, @recipient
view.subject
#=> "#{@email} vous a envoyé un secret"

## Can create a view for SecretLink with share_domain
@secret.share_domain = 'example.com'
@secret.save
view = OT::Mail::SecretLink.new @cust, @locale, @secret, @recipient
[view.uri_path, view[:secret].identifier, view[:email_address], view[:secret].share_domain]
#=> ["/secret/#{@secret.identifier}", @secret.identifier, @recipient, 'example.com']

## Renders correct subject for SecretLink with share_domain (English)
view = OT::Mail::SecretLink.new @cust, 'en', @secret, @recipient
view.subject
#=> "#{@email} sent you a secret"

## Renders correct subject for SecretLink with share_domain (French Canadian)
view = OT::Mail::SecretLink.new @cust, 'fr_CA', @secret, @recipient
view.subject
#=> "#{@email} vous a envoyé un secret"

## Includes share_domain in email body (English)
view = OT::Mail::SecretLink.new @cust, 'en', @secret, @recipient
view.render.include?("https://example.com/secret/#{@secret.key}")
#=> true

## Includes share_domain in email body (French Canadian)
view = OT::Mail::SecretLink.new @cust, 'fr_CA', @secret, @recipient
view.render.include?("https://example.com/secret/#{@secret.key}")
#=> true

# Teardown
@secret.destroy!
@cust.destroy!
