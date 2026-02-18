# try/unit/cli/email_send_command_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::CLI::EmailSendCommand class.
#
# Covers AVAILABLE_TEMPLATES, parse_and_merge_data, resolve_template,
# build_template, output_json, handle_argument_error, and invalid JSON.

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'onetime/mail'
require 'onetime/cli'

@cmd = Onetime::CLI::EmailSendCommand.new

# TRYOUTS

## AVAILABLE_TEMPLATES contains exactly 11 templates
Onetime::CLI::EmailSendCommand::AVAILABLE_TEMPLATES.size
#=> 11

## AVAILABLE_TEMPLATES includes secret_link
Onetime::CLI::EmailSendCommand::AVAILABLE_TEMPLATES.include?(:secret_link)
#=> true

## AVAILABLE_TEMPLATES includes welcome
Onetime::CLI::EmailSendCommand::AVAILABLE_TEMPLATES.include?(:welcome)
#=> true

## AVAILABLE_TEMPLATES includes email_change_confirmation
Onetime::CLI::EmailSendCommand::AVAILABLE_TEMPLATES.include?(:email_change_confirmation)
#=> true

## AVAILABLE_TEMPLATES is frozen
Onetime::CLI::EmailSendCommand::AVAILABLE_TEMPLATES.frozen?
#=> true

## AVAILABLE_TEMPLATES contains all expected symbols
expected = %i[
  secret_link welcome password_request incoming_secret
  feedback_email secret_revealed expiration_warning
  organization_invitation email_change_confirmation
  email_change_requested email_changed
]
(expected - Onetime::CLI::EmailSendCommand::AVAILABLE_TEMPLATES).empty?
#=> true

## parse_and_merge_data parses JSON and symbolizes keys
result = @cmd.send(:parse_and_merge_data, '{"name":"test"}', 'user@example.com')
result[:name]
#=> "test"

## parse_and_merge_data sets :recipient to the to address
result = @cmd.send(:parse_and_merge_data, '{"key":"val"}', 'user@example.com')
result[:recipient]
#=> "user@example.com"

## parse_and_merge_data sets :email_address to the to address
result = @cmd.send(:parse_and_merge_data, '{"key":"val"}', 'user@example.com')
result[:email_address]
#=> "user@example.com"

## parse_and_merge_data preserves all parsed keys
result = @cmd.send(:parse_and_merge_data, '{"a":"1","b":"2"}', 'r@x.com')
[result[:a], result[:b]]
#=> ["1", "2"]

## resolve_template returns correct class for secret_link
klass = @cmd.send(:resolve_template, 'secret_link')
klass
#=> Onetime::Mail::Templates::SecretLink

## resolve_template returns correct class for welcome
klass = @cmd.send(:resolve_template, 'welcome')
klass
#=> Onetime::Mail::Templates::Welcome

## resolve_template returns correct class for email_changed
klass = @cmd.send(:resolve_template, 'email_changed')
klass
#=> Onetime::Mail::Templates::EmailChanged

## resolve_template raises ArgumentError for unknown template
begin
  @cmd.send(:resolve_template, 'nonexistent')
rescue ArgumentError => e
  e.message
end
#=> "Unknown template: nonexistent"

## build_template instantiates template with data and locale
data = { new_email: 'new@example.com', confirmation_token: 'tok123' }
instance = @cmd.send(:build_template, Onetime::Mail::Templates::EmailChangeConfirmation, data, 'en')
instance.class
#=> Onetime::Mail::Templates::EmailChangeConfirmation

## build_template passes locale correctly
data = { new_email: 'new@example.com', confirmation_token: 'tok123' }
instance = @cmd.send(:build_template, Onetime::Mail::Templates::EmailChangeConfirmation, data, 'fr')
instance.locale
#=> "fr"

## build_template passes data correctly
data = { new_email: 'new@example.com', confirmation_token: 'tok123' }
instance = @cmd.send(:build_template, Onetime::Mail::Templates::EmailChangeConfirmation, data, 'en')
instance.data[:new_email]
#=> "new@example.com"

## Template validation raises for missing required data
begin
  Onetime::Mail::Templates::SecretLink.new({})
rescue ArgumentError => e
  e.message
end
#=> "Secret key required"

## output_json produces valid JSON with dry_run mode
require 'stringio'
email = { to: 'u@x.com', from: 'f@x.com', reply_to: nil, subject: 'S', text_body: 'T', html_body: nil }
captured = StringIO.new
old_stdout = $stdout
$stdout = captured
@cmd.send(:output_json, email, 'secret_link', false)
$stdout = old_stdout
parsed = JSON.parse(captured.string)
parsed['mode']
#=> "dry_run"

## output_json produces execute mode when execute is true
email = { to: 'u@x.com', from: 'f@x.com', reply_to: nil, subject: 'S', text_body: 'T', html_body: nil }
captured = StringIO.new
old_stdout = $stdout
$stdout = captured
@cmd.send(:output_json, email, 'secret_link', true)
$stdout = old_stdout
parsed = JSON.parse(captured.string)
parsed['mode']
#=> "execute"

## output_json includes template name in output
email = { to: 'u@x.com', from: 'f@x.com', reply_to: nil, subject: 'S', text_body: 'T', html_body: nil }
captured = StringIO.new
old_stdout = $stdout
$stdout = captured
@cmd.send(:output_json, email, 'welcome', false)
$stdout = old_stdout
parsed = JSON.parse(captured.string)
parsed['template']
#=> "welcome"

## Invalid JSON raises JSON::ParserError
begin
  @cmd.send(:parse_and_merge_data, '{invalid json}', 'user@example.com')
rescue JSON::ParserError
  'raised'
end
#=> "raised"

## EmailSendCommand inherits from Command
Onetime::CLI::EmailSendCommand.ancestors.include?(Onetime::CLI::Command)
#=> true

## EmailSendCommand is a Dry::CLI::Command
Onetime::CLI::EmailSendCommand.ancestors.include?(Dry::CLI::Command)
#=> true
