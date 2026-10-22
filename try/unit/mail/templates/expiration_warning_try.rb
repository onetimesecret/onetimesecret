# try/unit/mail/templates/expiration_warning_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::ExpirationWarning class.
#
# ExpirationWarning is used to notify secret owners that their secret
# is about to expire. The email links to the owner's receipt page.
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

@receipt_identifier = '0195f3a2-8c4e-7b1d-9a6f-2e3d4c5b6a70'

@valid_data = {
  recipient: 'owner@example.com',
  receipt_identifier: @receipt_identifier,
  expires_at: @expires_soon,
  share_domain: nil
}

@valid_data_with_domain = {
  recipient: 'owner@example.com',
  receipt_identifier: 'f0e1d2c3b4a5968778695a4b3c2d1e0f',
  expires_at: @expires_soon,
  share_domain: 'custom.example.com'
}

# Payload shape queued by the job before the receipt link: an 8-character
# secret shortid under secret_key and no receipt identifier.
@legacy_data = {
  recipient: 'owner@example.com',
  secret_key: 'abc123de',
  expires_at: @expires_soon,
  share_domain: nil
}

# TRYOUTS

## ExpirationWarning validates presence of recipient
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    receipt_identifier: @receipt_identifier,
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

## ExpirationWarning rejects an empty receipt_identifier
begin
  Onetime::Mail::Templates::ExpirationWarning.new(@valid_data.merge(receipt_identifier: ''))
rescue ArgumentError => e
  e.message
end
#=> 'Receipt identifier required'

## ExpirationWarning rejects a legacy secret_key payload instead of rendering a dead link
begin
  Onetime::Mail::Templates::ExpirationWarning.new(@legacy_data)
rescue ArgumentError => e
  e.message
end
#=> 'Receipt identifier required'

## ExpirationWarning validates presence of expires_at
begin
  Onetime::Mail::Templates::ExpirationWarning.new({
    recipient: 'test@example.com',
    receipt_identifier: @receipt_identifier
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

## ExpirationWarning uri_path is the receipt path with the full identifier
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.uri_path
#=> '/receipt/0195f3a2-8c4e-7b1d-9a6f-2e3d4c5b6a70'

## ExpirationWarning receipt_uri links to the canonical host by default
# receipt_uri is built from brand_baseuri, which falls back to the canonical
# site baseuri when the message carries no share_domain.
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.receipt_uri
#=~> /\Ahttps?:\/\/.+\/receipt\/0195f3a2-8c4e-7b1d-9a6f-2e3d4c5b6a70\z/

## ExpirationWarning receipt_uri links to the share_domain when present
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data_with_domain)
template.receipt_uri
#=> 'https://custom.example.com/receipt/f0e1d2c3b4a5968778695a4b3c2d1e0f'

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

## ExpirationWarning render_text contains the receipt URI
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.render_text.include?(template.receipt_uri)
#=> true

## ExpirationWarning render_text has no /secret/ link
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.render_text.include?('/secret/')
#=> false

## ExpirationWarning render_html links to the receipt URI
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.render_html.include?(%Q(href="#{template.receipt_uri}"))
#=> true

## ExpirationWarning render_html has no /secret/ link
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data)
template.render_html.include?('/secret/')
#=> false

## ExpirationWarning render_html links to the receipt on the share_domain
template = Onetime::Mail::Templates::ExpirationWarning.new(@valid_data_with_domain)
template.render_html.include?('href="https://custom.example.com/receipt/f0e1d2c3b4a5968778695a4b3c2d1e0f"')
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
#=~> /\Ahttps?:\/\/.+\/receipt\/0195f3a2-8c4e-7b1d-9a6f-2e3d4c5b6a70\z/
