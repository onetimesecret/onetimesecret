# try/unit/models/v2/app_settings_try.rb
#
# frozen_string_literal: true

# These tryouts test the functionality ofthe V2::Controllers::ClassSettings class.
#
# The ClassSettings module provides configuration options for UTF-8 and URI encoding
# middleware checks.
#
# We're testing various aspects of the ClassSettings module, including:
# 1. Default values for check_utf8 and check_uri_encoding
# 2. Setting and getting check_utf8 and check_uri_encoding values
# 3. Independence of settings between different classes
# 4. Behavior when including the module in multiple classes
#
# These tests aim to ensure that the ClassSettings module correctly manages
# configuration options for UTF-8 and URI encoding checks, which is crucial
# for properly handling incoming requests in the Onetime application.
#
# The tryouts simulate different scenarios of using the ClassSettings module
# without needing to run the full application, allowing for targeted testing
# of this specific functionality.

require_relative '../../../support/test_models'
require 'v2/controllers/class_settings'

OT.boot! :test, false

class TestApp
  include V2::Controllers::ClassSettings
end

class AnotherTestApp
  include V2::Controllers::ClassSettings
end

## Default values for check_utf8 and check_uri_encoding are nil
TestApp.check_utf8
#=> nil

## Default value for check_uri_encoding is nil
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

## Check UTF8 (before)
AnotherTestApp.check_utf8
#=> nil

## Check URI Encoding (before)
AnotherTestApp.check_uri_encoding
#=> nil

## Check UTF8 set different values for different classes
AnotherTestApp.check_utf8 = false
AnotherTestApp.check_utf8
#=> false

## Check URI set different values for different classes
AnotherTestApp.check_uri_encoding = true
AnotherTestApp.check_uri_encoding
#=> true

## Check UTF8
TestApp.check_utf8
#=> true

## Check URI Encoding
TestApp.check_uri_encoding
#=> false

## Check UTF8 for AnotherTestApp
AnotherTestApp.check_utf8
#=> false

## Check URI Encoding for AnotherTestApp
AnotherTestApp.check_uri_encoding
#=> true
