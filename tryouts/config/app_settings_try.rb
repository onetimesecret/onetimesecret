# tryouts/config/app_settings_try.rb

# These tryouts test the functionality of the AppSettings module in the Manifold::Views::BaseView class.
# The AppSettings module provides configuration options for UTF-8 and URI encoding
# middleware checks.
#
# We're testing various aspects of the AppSettings module, including:
# 1. Default values for check_utf8 and check_uri_encoding
# 2. Setting and getting check_utf8 and check_uri_encoding values
# 3. Independence of settings between different classes
# 4. Behavior when including the module in multiple classes
#
# These tests aim to ensure that the AppSettings module correctly manages
# configuration options for UTF-8 and URI encoding checks, which is crucial
# for properly handling incoming requests in the Onetime application.
#
# The tryouts simulate different scenarios of using the AppSettings module
# without needing to run the full application, allowing for targeted testing
# of this specific functionality.

require_relative '../helpers/test_models'
require 'v2/controllers/class_settings'

# Use the default config file for tests
OT.boot! :test, false

class TestApp
  include V2::Controllers::ClassSettings
end

## Default values for check_utf8 and check_uri_encoding are nil
TestApp.check_utf8
#=> nil

TestApp.check_uri_encoding
#=> nil

## Can set and get check_utf8
TestApp.check_utf8 = true
TestApp.check_utf8
#=> true

## Can set and get check_uri_encoding
TestApp.check_uri_encoding = false
TestApp.check_uri_encoding
#=> false

## Settings are independent for different classes
class AnotherTestApp
  include V2::Controllers::ClassSettings
end

AnotherTestApp.check_utf8
#=> nil

AnotherTestApp.check_uri_encoding
#=> nil

## Can set different values for different classes
AnotherTestApp.check_utf8 = false
AnotherTestApp.check_uri_encoding = true

TestApp.check_utf8
#=> true

TestApp.check_uri_encoding
#=> false

AnotherTestApp.check_utf8
#=> false

AnotherTestApp.check_uri_encoding
#=> true
