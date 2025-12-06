# try/unit/config/emailer_config_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'

OT.boot! :test, false

## Default emailer mode in test environment
OT.conf['emailer']['mode']
#=> 'logger'

## Default emailer from address in test environment
OT.conf['emailer']['from']
#=> "secure@onetime.dev"

## Default emailer from_name is "Jan"
OT.conf['emailer']['from_name']
#=> "Jan"

## Default SMTP host in test environment
OT.conf['emailer']['host']
#=> nil

## Default SMTP port in test environment
OT.conf['emailer']['port']
#=> nil

## SMTP username in test environment
OT.conf['emailer']['user']
#=> nil

## SMTP password in test environment
OT.conf['emailer']['pass']
#=> nil

## SMTP auth in test environment
OT.conf['emailer']['auth']
#=> nil

## SMTP TLS in test environment
OT.conf['emailer']['tls']
#=> nil

## Test environment config is loaded from etc/config.test.yaml
# These values match what's configured in etc/config.test.yaml which is loaded
# during boot when RACK_ENV=test. The .env.test file also sets some values
# but the YAML config file takes precedence for most settings.
true
#=> true
