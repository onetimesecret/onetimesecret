# tests/unit/ruby/try/test_helpers.rb

# A custom hash class that allows indifferent access to keys.
# Keys can be accessed using strings, symbols, or methods.
# Helpul
#
#
# Example:
#
#     http_response = IndifferentHash.new(
#       code: 403,
#       error: 'Forbidden',
#       body: 'You are not allowed to access this resource.'
#     )
#
#     http_response.code      # => 403
#     http_response[:error]   # => 'Forbidden'
#     http_response['body']   # => 'You are not allowed to access this resource.'
#
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..', '..', '..', '..')).freeze
project_root = ENV['ONETIME_HOME']
app_root = File.join(project_root, '/apps').freeze

$LOAD_PATH.unshift(File.join(app_root, 'api'))
$LOAD_PATH.unshift(File.join(app_root, 'web'))

require 'onetime'

OT::Config.path = File.join(project_root, 'tests', 'unit', 'ruby', 'config.test.yaml')
