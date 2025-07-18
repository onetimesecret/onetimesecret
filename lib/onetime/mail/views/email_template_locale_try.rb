# lib/onetime/mail/views/email_template_locale_try.rb

# These tryouts test the email template functionality in the Onetime application.
# They cover various aspects of email template handling, including:
#
# 1. Creating email views for different purposes (Welcome, SecretLink)
# 2. Rendering email templates
# 3. Handling different locales (English, Spanish)
# 4. Verifying email subject lines
#
# These tests aim to ensure that email templates are correctly generated and localized,
# which is crucial for effective communication with users in the application.
#
# The tryouts use the Onetime::Mail classes
#
# NOTE: Only locales that are configured in test config.test.yaml are
# available for use in testing. See the humphreybogus example below.

require_relative '../../../../tests/helpers/test_models'
# Use the default config file for tests
OT.boot! :test, false

@email = "tryouts+40+#{Time.now.to_i}@onetimesecret.com"
@cust = V1::Customer.new custid: @email # wrong, use spawn instead
@secret = V1::Secret.new # wrong and does generate secret key
@locale = 'es'

## Can create a view
view = OT::Mail::Welcome.new @cust, @locale, @secret
[view[:secret].identifier, view.verify_uri]
#=> [@secret.identifier, "/secret/#{@secret.identifier}"]

## Can create a view
view = OT::Mail::SecretLink.new @cust, @locale, @secret, 'tryouts+recipient@onetimesecret.com'
[view.uri_path, view[:secret].identifier, view[:email_address]]
#=> ["/secret/#{@secret.identifier}", @secret.identifier, "tryouts+recipient@onetimesecret.com"]

## Understands locale in english
view = OT::Mail::SecretLink.new @cust, 'en', @secret, 'tryouts+recipient@onetimesecret.com'
view.subject
#=> "#{@email} sent you a secret"

## Can quietly continue with the default locale when given some bad ham
view = OT::Mail::SecretLink.new @cust, 'humphreybogus', '', ''
view.locale
#=> 'en'

## Can receive and keep track of a locale
view = OT::Mail::SecretLink.new @cust, 'fr_CA', '', ''
view.locale
#=> 'fr_CA'

## Understands locale in spanish
view = OT::Mail::SecretLink.new @cust, 'fr_CA', @secret, 'tryouts+recipient@onetimesecret.com'
view.subject
#=> "#{@email} vous a envoyé un secret"
