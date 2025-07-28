# tests/unit/ruby/try/16_config_emailer_try.rb

require_relative 'test_helpers'

# Use the default config file for tests
OT.boot! :test, false

## Default emailer mode is :smtp
OT.conf[:emailer][:mode]
#=> 'smtp'

## Default emailer from address is "CHANGEME@example.com"
OT.conf[:emailer][:from]
#=> "tests@example.com"

## Default emailer fromname is "Jan"
OT.conf[:emailer][:fromname]
#=> "Jan"

## Default SMTP host is "localhost"
OT.conf[:emailer][:host]
#=> "localhost"

## Default SMTP port is 587
OT.conf[:emailer][:port]
#=> 587

## Default SMTP username is "CHANGEME"
OT.conf[:emailer][:user]
#=> "user"

## Default SMTP password is "CHANGEME"
OT.conf[:emailer][:pass]
#=> "pass"

## Default SMTP auth is "login"
OT.conf[:emailer][:auth]
#=> "login"

## Default SMTP TLS is true
OT.conf[:emailer][:tls]
#=> true

## Emailer raises an exception when the mode is not valid
ENV['EMAILER_MODE'] = 'bogus'
Onetime::Config.load
OT.boot! :test, false
##=> ''

## Emailer values can be set via environment variables
ENV['EMAILER_MODE'] = 'sendgrid'
ENV['FROM'] = 'tests@example.com'
ENV['FROMNAME'] = 'Test User'
ENV['SMTP_HOST'] = 'smtp.example.com'
ENV['SMTP_PORT'] = '465'
ENV['SMTP_USERNAME'] = 'testuser'
ENV['SMTP_PASSWORD'] = 'testpass'
ENV['SMTP_AUTH'] = 'plain'
ENV['SMTP_TLS'] = 'false'

Onetime::Config.load
OT.boot! :test, false

[
  OT.conf[:emailer][:mode],
  OT.conf[:emailer][:from],
  OT.conf[:emailer][:fromname],
  OT.conf[:emailer][:host],
  OT.conf[:emailer][:port],
  OT.conf[:emailer][:user],
  OT.conf[:emailer][:pass],
  OT.conf[:emailer][:auth],
  OT.conf[:emailer][:tls]
]
#=> ["sendgrid", "tests@example.com", "Test User", "smtp.example.com", 465, "testuser", "testpass", "plain", false]

## Clearing environment variables restores default values
ENV.delete('EMAILER_MODE')
ENV.delete('FROM')
ENV.delete('FROMNAME')
ENV.delete('SMTP_HOST')
ENV.delete('SMTP_PORT')
ENV.delete('SMTP_USERNAME')
ENV.delete('SMTP_PASSWORD')
ENV.delete('SMTP_AUTH')
ENV.delete('SMTP_TLS')

Onetime::Config.load
OT.boot! :test, false

[
  OT.conf[:emailer][:mode],
  OT.conf[:emailer][:from],
  OT.conf[:emailer][:fromname],
  OT.conf[:emailer][:host],
  OT.conf[:emailer][:port],
  OT.conf[:emailer][:user],
  OT.conf[:emailer][:pass],
  OT.conf[:emailer][:auth],
  OT.conf[:emailer][:tls]
]
#=> ["smtp", "tests@example.com", "Jan", "localhost", 587, "user", "pass", "login", true]
