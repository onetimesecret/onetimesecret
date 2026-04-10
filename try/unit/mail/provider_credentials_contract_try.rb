# try/unit/mail/provider_credentials_contract_try.rb
#
# frozen_string_literal: true

# Tests for the credential key contract between Mailer.build_provider_config
# and sender strategy consumers.
#
# Background: build_provider_config previously returned symbol keys (:team_token,
# :api_token, etc.) but strategy consumers accessed them with string keys
# ('team_token'). This mismatch caused provider verification to always fail
# because credentials['team_token'] was nil when the hash had :team_token.
#
# Convention: anything crossing an interface boundary uses string keys.
#
# Validates:
# 1. build_provider_config returns string keys for ALL providers
# 2. Lettermint credentials include team_token and api_token as string keys
# 3. SES credentials include region, access_key_id, secret_access_key as string keys
# 4. SendGrid credentials include api_key as string key
# 5. SMTP credentials include host, port, username, password as string keys
# 6. provider_credentials (public API) returns string keys
# 7. Strategy consumers can access credentials with string keys
# 8. No symbol keys leak into credential hashes

require_relative '../../support/test_helpers'

# Load the app
OT.boot! :test, false

# Load the mail module
require 'onetime/mail'

# Stub emailer config with values for all providers so build_provider_config
# can resolve credentials without hitting real environment variables.
@original_emailer_config = Onetime::Mail::Mailer.send(:emailer_config)

class Onetime::Mail::Mailer
  class << self
    def emailer_config
      {
        'mode' => 'logger',
        'from' => 'test@example.com',
        # SMTP
        'host' => 'smtp.example.com',
        'port' => 587,
        'user' => 'smtp_user',
        'pass' => 'smtp_pass',
        'domain' => 'example.com',
        'tls' => true,
        # SES
        'region' => 'us-east-1',
        # SendGrid
        'sendgrid_api_key' => 'SG.test-key',
        # Lettermint
        'lettermint_api_token' => 'lm-sending-token',
        'lettermint_team_token' => 'lm-team-token',
        'lettermint_base_url' => 'https://api.lettermint.co/v1',
        'lettermint_timeout' => 30,
      }
    end

    def provider_config(_provider)
      {}
    end
  end
end

# --- SMTP: string keys only ---

## SMTP config returns a Hash
@smtp_config = Onetime::Mail::Mailer.send(:build_provider_config, 'smtp')
@smtp_config.is_a?(Hash)
#=> true

## SMTP config has string key 'host'
@smtp_config.key?('host')
#=> true

## SMTP config has string key 'port'
@smtp_config.key?('port')
#=> true

## SMTP config has string key 'username'
@smtp_config.key?('username')
#=> true

## SMTP config has string key 'password'
@smtp_config.key?('password')
#=> true

## SMTP config has string key 'domain'
@smtp_config.key?('domain')
#=> true

## SMTP config has string key 'tls'
@smtp_config.key?('tls')
#=> true

## SMTP config contains NO symbol keys
@smtp_config.keys.none? { |k| k.is_a?(Symbol) }
#=> true

## SMTP host value is correct
@smtp_config['host']
#=> 'smtp.example.com'

# --- SES: string keys only ---

## SES config returns a Hash
@ses_config = Onetime::Mail::Mailer.send(:build_provider_config, 'ses')
@ses_config.is_a?(Hash)
#=> true

## SES config has string key 'region'
@ses_config.key?('region')
#=> true

## SES config has string key 'access_key_id'
@ses_config.key?('access_key_id')
#=> true

## SES config has string key 'secret_access_key'
@ses_config.key?('secret_access_key')
#=> true

## SES config contains NO symbol keys
@ses_config.keys.none? { |k| k.is_a?(Symbol) }
#=> true

## SES region value is correct
@ses_config['region']
#=> 'us-east-1'

# --- SendGrid: string keys only ---

## SendGrid config returns a Hash
@sg_config = Onetime::Mail::Mailer.send(:build_provider_config, 'sendgrid')
@sg_config.is_a?(Hash)
#=> true

## SendGrid config has string key 'api_key'
@sg_config.key?('api_key')
#=> true

## SendGrid config contains NO symbol keys
@sg_config.keys.none? { |k| k.is_a?(Symbol) }
#=> true

## SendGrid api_key value is correct
@sg_config['api_key']
#=> 'SG.test-key'

# --- Lettermint: string keys only ---

## Lettermint config returns a Hash
@lm_config = Onetime::Mail::Mailer.send(:build_provider_config, 'lettermint')
@lm_config.is_a?(Hash)
#=> true

## Lettermint config has string key 'api_token'
@lm_config.key?('api_token')
#=> true

## Lettermint config has string key 'team_token'
@lm_config.key?('team_token')
#=> true

## Lettermint config has string key 'base_url'
@lm_config.key?('base_url')
#=> true

## Lettermint config has string key 'timeout'
@lm_config.key?('timeout')
#=> true

## Lettermint config contains NO symbol keys
@lm_config.keys.none? { |k| k.is_a?(Symbol) }
#=> true

## Lettermint team_token value is correct
@lm_config['team_token']
#=> 'lm-team-token'

## Lettermint api_token value is correct
@lm_config['api_token']
#=> 'lm-sending-token'

# --- Logger: empty hash ---

## Logger config returns empty hash
@logger_config = Onetime::Mail::Mailer.send(:build_provider_config, 'logger')
@logger_config
#=> {}

# --- Unknown provider: empty hash ---

## Unknown provider returns empty hash
@unknown_config = Onetime::Mail::Mailer.send(:build_provider_config, 'unknown_provider')
@unknown_config
#=> {}

# --- Public API: provider_credentials returns string keys ---

## provider_credentials for lettermint returns string keys
@public_lm = Onetime::Mail::Mailer.provider_credentials('lettermint')
@public_lm.key?('team_token') && @public_lm.key?('api_token')
#=> true

## provider_credentials for ses returns string keys
@public_ses = Onetime::Mail::Mailer.provider_credentials('ses')
@public_ses.key?('region')
#=> true

## provider_credentials for sendgrid returns string keys
@public_sg = Onetime::Mail::Mailer.provider_credentials('sendgrid')
@public_sg.key?('api_key')
#=> true

# --- Contract: strategy consumers can use string key access ---

## Lettermint credentials team_token accessible via string key (the bug scenario)
creds = Onetime::Mail::Mailer.provider_credentials('lettermint')
creds['team_token'].nil? == false
#=> true

## Lettermint credentials team_token is the expected value
creds = Onetime::Mail::Mailer.provider_credentials('lettermint')
creds['team_token']
#=> 'lm-team-token'

## Lettermint credentials api_token accessible via string key
creds = Onetime::Mail::Mailer.provider_credentials('lettermint')
creds['api_token']
#=> 'lm-sending-token'

## SES credentials region accessible via string key
creds = Onetime::Mail::Mailer.provider_credentials('ses')
creds['region']
#=> 'us-east-1'

## SendGrid credentials api_key accessible via string key
creds = Onetime::Mail::Mailer.provider_credentials('sendgrid')
creds['api_key']
#=> 'SG.test-key'
