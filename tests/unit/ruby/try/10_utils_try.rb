# tests/unit/ruby/try/10_utils_try.rb

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

# Running:
#
# $ RUBYLIB=./lib bundle exec try -v ./try/10_utils_try.rb
#

require_relative './test_helpers'

# Familia.debug = true
# require 'onetime/models'

# Use the default config file for tests

OT.boot! :test, false

## Create a strand
Onetime::Utils.strand.class
#=> String

## strand is 12 chars by default
Onetime::Utils.strand.size
#=> 12

## strand can be n chars
Onetime::Utils.strand(20).size
#=> 20

## Obscure email address (6 or more chars)
Onetime::Utils.obscure_email('tryouts@onetimesecret.com')
#=> 'tr*****@o*****.com'

## Obscure email address (4 or more chars)
Onetime::Utils.obscure_email('dave@onetimesecret.com')
#=> 'da*****@o*****.com'

## Obscure email address (less than 4 chars)
Onetime::Utils.obscure_email('dm@onetimesecret.com')
#=> 'dm*****@o*****.com'

## Obscure email address (single char)
Onetime::Utils.obscure_email('r@onetimesecret.com')
#=> 'r*****@o*****.com'

## Obscure email address (Long)
Onetime::Utils.obscure_email('readyreadyreadyready@onetimesecretonetimesecretonetimesecret.com')
#=> 're*****@o*****.com'
