# try/unit/mail/templates/expiration_warning_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::ExpirationWarning class.
#
# ExpirationWarning is used to notify secret owners that their secret
# is about to expire. An account notification: it names the secret by its
# short id and links to the owner's recent-secrets page on the canonical
# host. It carries no receipt or secret identifier (both are bearer
# capabilities for the secret).
#
# Required data: recipient, secret_shortid, expires_at
# Optional: baseuri

require 'uri'

require_relative '../../../support/test_helpers'

# Load the app to get templates and config
OT.boot! :test, false

# Load the mail module explicitly
require 'onetime/mail'

# Expiration in 2 hours from now
@expires_soon = Time.now.to_i + 7200

@valid_data = {
  recipient: 'owner@example.com',
  secret_shortid: 'a1b2c3d4',
  expires_at: @expires_soon
}

# TRYOUTS

## ExpirationWarning validates presence of recipient
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    secret_shortid: 'a1b2c3d4',
    expires_at: @expires_soon
  })
rescue ArgumentError => e
  e.message
end
#=> 'Recipient required'

## ExpirationWarning validates presence of secret_shortid
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    recipient: 'test@example.com',
    expires_at: @expires_soon
  })
rescue ArgumentError => e
  e.message
end
#=> 'Secret short id required'

## ExpirationWarning rejects an empty secret_shortid
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    recipient: 'test@example.com',
    secret_shortid: '',
    expires_at: @expires_soon
  })
rescue ArgumentError => e
  e.message
end
#=> 'Secret short id required'

## ExpirationWarning rejects the previous payload shape (secret_key, no secret_shortid)
# A message queued by the previous job version carries the short id under
# secret_key. EmailWorker does not retry an ArgumentError, so the message is
# rejected instead of being sent.
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    recipient: 'test@example.com',
    secret_key: 'a1b2c3d4',
    expires_at: @expires_soon
  })
rescue ArgumentError => e
  e.message
end
#=> 'Secret short id required'

## ExpirationWarning validates presence of expires_at
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    recipient: 'test@example.com',
    secret_shortid: 'a1b2c3d4'
  })
rescue ArgumentError => e
  e.message
end
#=> 'Expiration time required'

## ExpirationWarning accepts valid data without error
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.class
#=> Onetime::Mail::Templates::ExpirationWarning

## ExpirationWarning subject is fixed text
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.subject
#=> 'Your secret link will expire soon'

## ExpirationWarning recipient_email returns recipient from data
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.recipient_email
#=> 'owner@example.com'

## ExpirationWarning secret_shortid returns the short id from data
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.secret_shortid
#=> 'a1b2c3d4'

## ExpirationWarning time_remaining shows hours when > 1 hour
data = @valid_data.merge(expires_at: Time.now.to_i + 7200) # 2 hours
template = Onetime::Mail::Templates::ExpirationWarning.new(data)
template.time_remaining
#=~> /\d+ hours?/

## ExpirationWarning time_remaining shows minutes when < 1 hour
data = @valid_data.merge(expires_at: Time.now.to_i + 1800) # 30 minutes
template = Onetime::Mail::Templates::ExpirationWarning.new(data)
template.time_remaining
#=~> /\d+ minutes?/

## ExpirationWarning time_remaining shows days when >= 24 hours
data = @valid_data.merge(expires_at: Time.now.to_i + 172800) # 48 hours
template = Onetime::Mail::Templates::ExpirationWarning.new(data)
template.time_remaining
#=~> /\d+ days?/

## ExpirationWarning time_remaining shows 'soon' when expired
data = @valid_data.merge(expires_at: Time.now.to_i - 100) # Already expired
template = Onetime::Mail::Templates::ExpirationWarning.new(data)
template.time_remaining
#=> 'soon'

## ExpirationWarning recent_uri is the recent-secrets page on the canonical host
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.recent_uri
#=~> /\Ahttps?:\/\/.+\/recent\z/

## ExpirationWarning recent_uri ignores share_domain
# Nothing sends share_domain any more. A payload that still carries one does
# not move the link: the owner signs in on the canonical host.
data = @valid_data.merge(share_domain: 'custom.example.com')
template = Onetime::Mail::Templates::ExpirationWarning.new(data)
uri = URI.parse(template.recent_uri)
[uri.host == 'custom.example.com', template.recent_uri == "#{template.baseuri}/recent"]
#=> [false, true]

## ExpirationWarning baseuri uses site config by default
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.baseuri
#=~> /https?:\/\/.+/

## ExpirationWarning baseuri respects data override
data = @valid_data.merge(baseuri: 'https://override.example.com')
template = Onetime::Mail::Templates::ExpirationWarning.new(data)
template.baseuri
#=> 'https://override.example.com'

## ExpirationWarning recent_uri follows the baseuri override
data = @valid_data.merge(baseuri: 'https://override.example.com')
template = Onetime::Mail::Templates::ExpirationWarning.new(data)
template.recent_uri
#=> 'https://override.example.com/recent'

## ExpirationWarning render_text returns string
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.render_text.class
#=> String

## ExpirationWarning render_text has the recent-secrets link and the short id, and no identifier path
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
text = template.render_text
[text.include?('/recent'), text.include?('a1b2c3d4'), text.include?('/secret/'), text.include?('/receipt/')]
#=> [true, true, false, false]

## ExpirationWarning render_html has the recent-secrets link and the short id, and no identifier path
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
html = template.render_html
[html.include?('/recent'), html.include?('a1b2c3d4'), html.include?('/secret/'), html.include?('/receipt/')]
#=> [true, true, false, false]

## ExpirationWarning render_text contains expiration message
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.render_text.include?('expire')
#=> true

## ExpirationWarning render_html returns string or nil
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
result = template.render_html
result.nil? || result.is_a?(String)
#=> true

## ExpirationWarning to_email returns complete email hash
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
email = template.to_email(from: 'noreply@example.com')
[email[:to], email[:from], email[:subject].include?('expire')]
#=> ['owner@example.com', 'noreply@example.com', true]

## ExpirationWarning to_email includes text_body
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
email = template.to_email(from: 'noreply@example.com')
email[:text_body].is_a?(String) && !email[:text_body].empty?
#=> true
