# try/test_helpers.rb

require 'securerandom'

ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..')).freeze
project_root = ENV['ONETIME_HOME']
app_root = File.join(project_root, '/apps').freeze

# Generate a 64-character random AUTH_SECRET for tests if not already set
ENV['AUTH_SECRET'] ||= SecureRandom.hex(32)

$LOAD_PATH.unshift(File.join(app_root, 'api'))
$LOAD_PATH.unshift(File.join(app_root, 'web'))

require 'onetime'
require 'onetime/models'

OT::Config.path = File.join(project_root, 'spec', 'config.test.yaml')
