# try/unit/mail/templates/expiration_warning_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::ExpirationWarning class.
#
# ExpirationWarning is used to notify secret owners that their secret
# is about to expire. It links to the owner's receipt page.
#
# Required data: recipient, receipt_identifier, expires_at
# Optional: share_domain, baseuri

require_relative '../../../support/test_helpers'

# Load the app to get templates and config
OT.boot! :test, false

# Load the mail module explicitly
require 'onetime/mail'

# Expiration in 2 hours from now
@expires_soon = Time.now.to_i + 7200

@valid_data = {
  recipient: 'owner@example.com',
  receipt_identifier: 'abc123def456',
  expires_at: @expires_soon,
  share_domain: nil
}

@valid_data_with_domain = {
  recipient: 'owner@example.com',
  receipt_identifier: 'xyz789',
  expires_at: @expires_soon,
  share_domain: 'custom.example.com'
}

# TRYOUTS

## ExpirationWarning validates presence of recipient
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    receipt_identifier: 'abc123',
    expires_at: @expires_soon
  })
rescue ArgumentError => e
  e.message
end
#=> 'Recipient required'

## ExpirationWarning validates presence of receipt_identifier
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    recipient: 'test@example.com',
    expires_at: @expires_soon
  })
rescue ArgumentError => e
  e.message
end
#=> 'Receipt identifier required'

## ExpirationWarning rejects an empty receipt_identifier (it would build /receipt/)
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    recipient: 'test@example.com',
    receipt_identifier: '',
    expires_at: @expires_soon
  })
rescue ArgumentError => e
  e.message
end
#=> 'Receipt identifier required'

## ExpirationWarning rejects the previous payload shape (secret_key short id, no receipt)
# A message queued by the previous job version carries only the secret's
# short id, which no route resolves. EmailWorker does not retry an
# ArgumentError, so the message is rejected instead of sent with a dead link.
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    recipient: 'test@example.com',
    secret_key: 'abc12345',
    expires_at: @expires_soon
  })
rescue ArgumentError => e
  e.message
end
#=> 'Receipt identifier required'

## ExpirationWarning validates presence of expires_at
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    recipient: 'test@example.com',
    receipt_identifier: 'abc123'
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

## ExpirationWarning receipt_uri is the receipt page for the receipt identifier
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.receipt_uri
#=~> /\/receipt\/abc123def456\z/

## ExpirationWarning receipt_uri links to the canonical host by default
# receipt_uri is built from brand_baseuri, which falls back to the canonical
# site baseuri when the message carries no share_domain.
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.receipt_uri
#=~> /\Ahttps?:\/\/.+\/receipt\/abc123def456\z/

## ExpirationWarning receipt_uri links to the share_domain when present
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data_with_domain)
template.receipt_uri
#=> 'https://custom.example.com/receipt/xyz789'

## ExpirationWarning baseuri uses site config by default
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.baseuri
#=~> /https?:\/\/.+/

## ExpirationWarning baseuri respects data override
data = @valid_data.merge(baseuri: 'https://override.example.com')
template = Onetime::Mail::Templates::ExpirationWarning.new(data)
template.baseuri
#=> 'https://override.example.com'

## ExpirationWarning render_text returns string
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.render_text.class
#=> String

## ExpirationWarning render_text contains the receipt URI and no secret link
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
text = template.render_text
[text.include?('/receipt/abc123def456'), text.include?('/secret/')]
#=> [true, false]

## ExpirationWarning render_html links to the receipt URI
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.render_html.include?('/receipt/abc123def456')
#=> true

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

## ExpirationWarning handles nil share_domain gracefully
data = @valid_data.merge(share_domain: nil)
template = Onetime::Mail::Templates::ExpirationWarning.new(data)
template.receipt_uri
#=~> /\Ahttps?:\/\/.+\/receipt\/abc123def456\z/
