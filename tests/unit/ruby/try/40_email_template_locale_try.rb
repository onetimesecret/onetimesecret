# tests/unit/ruby/try/40_email_template_locale_try.rb

# These tryouts test the email template functionality in the OneTime application.
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
# The tryouts use the OT::Email classes

require_relative './test_helpers'

# Use the default config file for tests
OT.boot! :test

@email = 'tryouts+40@onetimesecret.com'
@cust = OT::Customer.new custid: @email # wrong, use spawn instead
@secret = OT::Secret.new # wrong and does generate secret key
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

## Understands locale in spanish
view = OT::Mail::SecretLink.new @cust, 'es', @secret, 'tryouts+recipient@onetimesecret.com'
view.subject
#=> "#{@email} le ha enviado un secreto"
