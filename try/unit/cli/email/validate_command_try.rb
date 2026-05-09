# try/unit/cli/email/validate_command_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::CLI::Email::ValidateCommand class.
#
# Tests private helper methods: determine_mode
# Full integration tests with Truemail mocking are in spec/cli/email_validate_command_spec.rb

require_relative '../../../support/test_helpers'

OT.boot! :test, false

require 'onetime/cli'

@cmd = Onetime::CLI::Email::ValidateCommand.new

# TRYOUTS

## ValidateCommand class exists
defined?(Onetime::CLI::Email::ValidateCommand)
#=> "constant"

## ValidateCommand inherits from Command
Onetime::CLI::Email::ValidateCommand.superclass
#=> Onetime::CLI::Command

## MODES constant contains expected validation types
Onetime::CLI::Email::ValidateCommand::MODES
#=> [:smtp, :mx, :regex]

## determine_mode returns :smtp when smtp flag is true
@cmd.send(:determine_mode, true, false, false)
#=> :smtp

## determine_mode returns :regex when regex flag is true (smtp false)
@cmd.send(:determine_mode, false, false, true)
#=> :regex

## determine_mode returns :mx when mx flag is true (others false)
@cmd.send(:determine_mode, false, true, false)
#=> :mx

## determine_mode defaults to :mx when no flags set
@cmd.send(:determine_mode, false, false, false)
#=> :mx

## determine_mode prioritizes smtp over mx and regex
@cmd.send(:determine_mode, true, true, true)
#=> :smtp

## determine_mode prioritizes regex over mx when smtp false
@cmd.send(:determine_mode, false, true, true)
#=> :regex

## extract_list_config returns hash with expected keys
config_mock = Struct.new(
  :whitelisted_emails, :blacklisted_emails,
  :whitelisted_domains, :blacklisted_domains
).new([], [], [], [])
allow_truemail_config = -> { config_mock }
Truemail.define_singleton_method(:configuration, &allow_truemail_config)

result = @cmd.send(:extract_list_config)
result.keys.sort
#=> [:blacklisted_domains, :blacklisted_emails, :whitelisted_domains, :whitelisted_emails]

## extract_list_config returns arrays for all values
result = @cmd.send(:extract_list_config)
result.values.all? { |v| v.is_a?(Array) }
#=> true

## extract_list_config preserves configured values
config_mock = Struct.new(
  :whitelisted_emails, :blacklisted_emails,
  :whitelisted_domains, :blacklisted_domains
).new(['allowed@test.com'], ['blocked@test.com'], ['trusted.com'], ['spam.com'])
Truemail.define_singleton_method(:configuration) { config_mock }

result = @cmd.send(:extract_list_config)
[result[:whitelisted_emails], result[:blacklisted_domains]]
#=> [["allowed@test.com"], ["spam.com"]]
