# try/unit/mail/delivery_logger_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Delivery::Logger class.
#
# Logger is the development/testing backend that outputs email
# content to logs instead of sending. Used when RACK_ENV=test
# or when no other backend is configured.

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module explicitly
require 'onetime/mail'

@test_email = {
  to: 'recipient@test.com',
  from: 'sender@test.com',
  reply_to: 'reply@test.com',
  subject: 'Test Subject',
  text_body: 'Plain text body content',
  html_body: '<html><body>HTML body</body></html>'
}

@minimal_email = {
  to: 'minimal@test.com',
  from: 'sender@test.com',
  subject: 'Minimal',
  text_body: 'Body'
}

# TRYOUTS

## Logger backend can be instantiated with empty config
backend = Onetime::Mail::Delivery::Logger.new({})
backend.class
#=> Onetime::Mail::Delivery::Logger

## Logger backend inherits from Base
backend = Onetime::Mail::Delivery::Logger.new({})
backend.is_a?(Onetime::Mail::Delivery::Base)
#=> true

## Logger backend provider_name returns 'Logger'
backend = Onetime::Mail::Delivery::Logger.new({})
backend.provider_name
#=> 'Logger'

## Logger deliver returns hash with status 'logged'
backend = Onetime::Mail::Delivery::Logger.new({})
result = backend.deliver(@test_email)
result[:status]
#=> 'logged'

## Logger deliver returns recipient in result
backend = Onetime::Mail::Delivery::Logger.new({})
result = backend.deliver(@test_email)
result[:to]
#=> 'recipient@test.com'

## Logger deliver handles missing reply_to
backend = Onetime::Mail::Delivery::Logger.new({})
result = backend.deliver(@minimal_email)
result[:status]
#=> 'logged'

## Logger deliver handles missing html_body
email_no_html = @test_email.merge(html_body: nil)
backend = Onetime::Mail::Delivery::Logger.new({})
result = backend.deliver(email_no_html)
result[:status]
#=> 'logged'

## Logger deliver handles empty html_body
email_empty_html = @test_email.merge(html_body: '')
backend = Onetime::Mail::Delivery::Logger.new({})
result = backend.deliver(email_empty_html)
result[:status]
#=> 'logged'

## Logger config is stored
backend = Onetime::Mail::Delivery::Logger.new({ custom: 'value' })
backend.config[:custom]
#=> 'value'

## Base normalize_email converts values to strings
backend = Onetime::Mail::Delivery::Logger.new({})
email = { to: :symbol, from: :symbol, subject: :symbol, text_body: :body }
normalized = backend.send(:normalize_email, email)
normalized[:to].class
#=> String

## Base html_content? returns false for nil html_body
backend = Onetime::Mail::Delivery::Logger.new({})
backend.send(:html_content?, { html_body: nil })
#=> false

## Base html_content? returns false for empty html_body
backend = Onetime::Mail::Delivery::Logger.new({})
backend.send(:html_content?, { html_body: '' })
#=> false

## Base html_content? returns true for non-empty html_body
backend = Onetime::Mail::Delivery::Logger.new({})
backend.send(:html_content?, { html_body: '<html></html>' })
#=> true

## Base obscure_email masks email (OT::Utils version may mask domain too)
backend = Onetime::Mail::Delivery::Logger.new({})
result = backend.send(:obscure_email, 'testuser@example.com')
result.include?('*') && result.include?('@')
#=> true
