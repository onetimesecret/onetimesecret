# try/unit/utils/utils_try.rb
#
# frozen_string_literal: true

# These tryouts test the functionality of the Onetime::Utils module.
# The Utils module provides various utility functions used throughout
# the Onetime application.
#
# We're testing various aspects of the Utils module, including:
# 1. Generation of random strands
# 2. Email address obfuscation
#
# These tests aim to ensure that the utility functions work correctly,
# which is crucial for various operations in the Onetime application,
# such as generating unique identifiers and protecting user privacy.
#
# The tryouts simulate different scenarios of using the Utils module
# without needing to run the full application, allowing for targeted
# testing of these specific functionalities.

require_relative '../../support/test_helpers'

# Familia.debug = true



OT.boot! :test, false
@original_fortunes = Onetime::Utils.instance_variable_get(:@fortunes)

## Create a strand
Onetime::Utils.strand.class
#=> String

## strand is 12 chars by default
Onetime::Utils.strand.size
#=> 12

## strand can be n chars
Onetime::Utils.strand(20).size
#=> 20

## Obscure email address (standard email)
Onetime::Utils.obscure_email('tryouts@onetimesecret.com')
#=> 'tr***@o***.com'

## Obscure email address (4 chars local)
Onetime::Utils.obscure_email('dave@onetimesecret.com')
#=> 'da***@o***.com'

## Obscure email address (2 chars local - at MIN_LOCAL threshold)
Onetime::Utils.obscure_email('dm@onetimesecret.com')
#=> 'dm@o***.com'

## Obscure email address (single char local - below MIN_LOCAL)
Onetime::Utils.obscure_email('r@onetimesecret.com')
#=> 'r@o***.com'

## Obscure email address (long local and domain)
Onetime::Utils.obscure_email('readyreadyreadyready@onetimesecretonetimesecretonetimesecret.com')
#=> 're***@o***.com'

## Obscure email in sentence context
Onetime::Utils.obscure_email('Contact tom@myspace.com please')
#=> 'Contact to***@m***.com please'

## Obscure email with country-code TLD (.co.uk)
Onetime::Utils.obscure_email('user@example.co.uk')
#=> 'us***@e***.co.uk'

## Obscure email with subdomain
Onetime::Utils.obscure_email('admin@mail.example.org')
#=> 'ad***@m***.org'

## Obscure multiple emails in text
Onetime::Utils.obscure_email('From: alice@foo.com To: bob@bar.org')
#=> 'From: al***@f***.com To: bo***@b***.org'

## Obscure email with plus addressing
Onetime::Utils.obscure_email('user+tag@example.com')
#=> 'us***@e***.com'

## Obscure email with dots in local part
Onetime::Utils.obscure_email('first.last@example.com')
#=> 'fi***@e***.com'

## Handle nil input gracefully
Onetime::Utils.obscure_email(nil)
#=> nil

## Handle empty string gracefully
Onetime::Utils.obscure_email('')
#=> ''

## Handle text without email addresses
Onetime::Utils.obscure_email('No email here')
#=> 'No email here'

## Handle complex TLD (.com.au)
Onetime::Utils.obscure_email('user@domain.com.au')
#=> 'us***@d***.com.au'

## random_fortune returns a string
## Create a mock fortunes collection
mock_fortunes = ["Fortune favors the bold.", "The early bird gets the worm."]
Onetime::Utils.fortunes = mock_fortunes
Onetime::Utils.random_fortune.class
#=> String

## random_fortune returns a trimmed fortune
## With trailing whitespace
mock_fortunes = ["Fortune with trailing space   "]
Onetime::Utils.fortunes = mock_fortunes
Onetime::Utils.random_fortune
#=> "Fortune with trailing space"

## random_fortune handles errors gracefully
## Create object that will raise error when random is called
error_fortunes = Object.new
def error_fortunes.random
  raise StandardError, "Test error"
end
Onetime::Utils.fortunes = error_fortunes
Onetime::Utils.random_fortune
#=> "Unexpected outcomes bring valuable lessons."

Onetime::Utils.instance_variable_set(:@fortunes, @original_fortunes)
