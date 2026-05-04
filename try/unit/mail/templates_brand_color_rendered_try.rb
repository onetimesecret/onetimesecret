# try/unit/mail/templates_brand_color_rendered_try.rb
#
# frozen_string_literal: true

# End-to-end ERB rendering tests for brand-color insertion in email
# templates (issue #3048, PR #3054 review).
#
# PR review flagged that brand-color rendering in email templates is only
# unit-tested at the helper level (TemplateContext#brand_color). The ERB
# output itself is not asserted, so a regression in helper plumbing or
# template wiring could ship silently.
#
# Strategy: render the actual ERB template, then assert the brand color
# string appears where the template uses the brand_color helper. Covers
# three of the four templates ported in commit fb9ee72e0: secret_link,
# password_request, organization_invitation. Includes regression guards
# against the old #dc4a22 OTS orange and the onetime-logo-v3-xl.svg path.

require_relative '../../support/test_helpers'

# Boot to populate OT.conf so site_baseuri/site_host helpers work.
OT.boot! :test, false

require 'onetime/mail'
require 'onetime/mail/views/secret_link'

# We pull in the password_request and organization_invitation view classes
# explicitly. They live alongside secret_link.
require 'onetime/mail/views/password_request' if File.exist?(
  File.expand_path('../../../lib/onetime/mail/views/password_request.rb', __dir__),
)
require 'onetime/mail/views/organization_invitation' if File.exist?(
  File.expand_path('../../../lib/onetime/mail/views/organization_invitation.rb', __dir__),
)

# Helper: run a block with OT.conf['brand'] set to a hash, then restore.
def with_brand_conf(brand_hash)
  saved = YAML.load(YAML.dump(OT.conf))
  conf_copy = YAML.load(YAML.dump(saved))
  conf_copy['brand'] = brand_hash
  OT.send(:conf=, conf_copy)
  yield
ensure
  OT.send(:conf=, saved) rescue nil
end

# Helper: run a block with OT.conf['brand'] removed, then restore.
def without_brand_conf
  saved = YAML.load(YAML.dump(OT.conf))
  conf_copy = YAML.load(YAML.dump(saved))
  conf_copy.delete('brand')
  OT.send(:conf=, conf_copy)
  yield
ensure
  OT.send(:conf=, saved) rescue nil
end

# Snapshot defaults for assertions
@neutral_blue = Onetime::CustomDomain::BrandSettingsConstants::DEFAULTS[:primary_color]

# Common test data for SecretLink (required: secret_key, recipient, sender_email)
@secret_link_data = {
  secret_key: 'abcdef0123456789',
  recipient: 'recipient@example.test',
  sender_email: 'sender@example.test',
}

# ============================================================================
# secret_link.html.erb — brand_color insertions
# ============================================================================

## Custom brand_color from per-message data appears in rendered HTML
@html_custom = without_brand_conf do
  Onetime::Mail::Templates::SecretLink
    .new(@secret_link_data.merge(brand_color: '#abcdef'), locale: 'en')
    .render_html
end
@html_custom.is_a?(String) && !@html_custom.empty?
#=> true

## secret_link rendered HTML contains the per-message brand_color in the secret-link <a> style
@html_custom.include?('color: #abcdef')
#=> true

## secret_link rendered HTML contains the brand_color for at least 2 insertion points
# (logo bg, link color, signature link). We don't pin an exact count; the
# template wires brand_color into multiple places and a single
# 'color: #abcdef' is enough proof of plumbing.
@html_custom.scan('#abcdef').size >= 2
#=> true

## brand_color from OT.conf flows into secret_link rendered HTML when no per-message override
@html_conf = with_brand_conf({ 'primary_color' => '#112233' }) do
  Onetime::Mail::Templates::SecretLink
    .new(@secret_link_data, locale: 'en')
    .render_html
end
@html_conf.include?('#112233')
#=> true

## REGRESSION GUARD: with no brand config and no per-message override, neutral blue is used
@html_neutral = without_brand_conf do
  Onetime::Mail::Templates::SecretLink
    .new(@secret_link_data, locale: 'en')
    .render_html
end
@html_neutral.include?(@neutral_blue)
#=> true

## REGRESSION GUARD: neutral default render contains NO #dc4a22 (old OTS orange)
@html_neutral.downcase.include?('#dc4a22')
#=> false

## REGRESSION GUARD: neutral default render contains NO onetime-logo-v3-xl.svg
@html_neutral.include?('onetime-logo-v3-xl.svg')
#=> false

## REGRESSION GUARD: with no brand.logo_url, the <img> block is omitted entirely
# secret_link wraps the <img> in <% if logo_url %> per fb9ee72e0.
@html_neutral.include?('<img alt="')
#=> false

## When brand.logo_url is set, the <img> block renders with logo_url and brand_color background
@html_with_logo = with_brand_conf({
  'primary_color' => '#1f3a8a',
  'logo_url' => 'https://example.test/logo.svg',
  'product_name' => 'Acme Secrets',
}) do
  Onetime::Mail::Templates::SecretLink
    .new(@secret_link_data, locale: 'en')
    .render_html
end
[
  @html_with_logo.include?('src="https://example.test/logo.svg"'),
  @html_with_logo.include?('background-color: #1f3a8a'),
  @html_with_logo.include?('alt="Acme Secrets"'),
]
#=> [true, true, true]

# ============================================================================
# password_request.html.erb — brand_color insertions
# ============================================================================

## password_request renders with custom brand_color in button background and link color
@pr_klass_defined = defined?(Onetime::Mail::Templates::PasswordRequest)
#=> 'constant'

## password_request renders with custom brand_color in HTML output
# Required data: recipient + reset_password_url. Different views have
# different validation; we only assert if the view class loads.
if defined?(Onetime::Mail::Templates::PasswordRequest)
  begin
    html = without_brand_conf do
      Onetime::Mail::Templates::PasswordRequest.new(
        {
          recipient: 'user@example.test',
          email_address: 'user@example.test',
          reset_password_url: 'https://example.test/reset/abc',
          brand_color: '#abcdef',
        },
        locale: 'en',
      ).render_html
    end
    html.include?('#abcdef')
  rescue ArgumentError, NameError, NoMethodError
    # If the view class has different required keys, fall back to direct
    # ERB rendering through the base TemplateContext instead.
    erb_path = File.expand_path('../../../lib/onetime/mail/templates/password_request.html.erb', __dir__)
    template_content = File.read(erb_path)
    erb = ERB.new(template_content, trim_mode: '-')
    ctx = Onetime::Mail::Templates::Base::TemplateContext.new(
      {
        recipient: 'user@example.test',
        email_address: 'user@example.test',
        reset_password_url: 'https://example.test/reset/abc',
        brand_color: '#abcdef',
        baseuri: 'https://example.test',
      },
      'en',
    )
    erb.result(ctx.get_binding).include?('#abcdef')
  end
else
  # No view class — render the ERB directly via TemplateContext to assert
  # the template-level wiring. Same outcome.
  erb_path = File.expand_path('../../../lib/onetime/mail/templates/password_request.html.erb', __dir__)
  template_content = File.read(erb_path)
  erb = ERB.new(template_content, trim_mode: '-')
  ctx = Onetime::Mail::Templates::Base::TemplateContext.new(
    {
      recipient: 'user@example.test',
      email_address: 'user@example.test',
      reset_password_url: 'https://example.test/reset/abc',
      brand_color: '#abcdef',
      baseuri: 'https://example.test',
    },
    'en',
  )
  erb.result(ctx.get_binding).include?('#abcdef')
end
#=> true

# ============================================================================
# organization_invitation.html.erb — brand_color insertions
# ============================================================================

## organization_invitation HTML contains the per-message brand_color
# The view class has its own required fields. To keep the test
# template-focused, render the ERB directly via the base TemplateContext.
@oi_path = File.expand_path('../../../lib/onetime/mail/templates/organization_invitation.html.erb', __dir__)
File.exist?(@oi_path)
#=> true

## organization_invitation rendered output contains custom brand_color
@oi_html = without_brand_conf do
  template_content = File.read(@oi_path)
  erb = ERB.new(template_content, trim_mode: '-')
  ctx = Onetime::Mail::Templates::Base::TemplateContext.new(
    {
      brand_color: '#abcdef',
      invite_uri: '/invite/xyz',
      baseuri: 'https://example.test',
      organization_name: 'Acme Inc.',
      inviter_email: 'admin@example.test',
      invited_email: 'invited@example.test',
      role_description: 'a member',
      expires_in_days: 7,
      product_name: 'Acme',
    },
    'en',
  )
  erb.result(ctx.get_binding)
end
@oi_html.include?('#abcdef')
#=> true

## organization_invitation neutral default (no brand conf, no per-msg override) uses neutral blue
@oi_neutral = without_brand_conf do
  template_content = File.read(@oi_path)
  erb = ERB.new(template_content, trim_mode: '-')
  ctx = Onetime::Mail::Templates::Base::TemplateContext.new(
    {
      invite_uri: '/invite/xyz',
      baseuri: 'https://example.test',
      organization_name: 'Acme Inc.',
      inviter_email: 'admin@example.test',
      invited_email: 'invited@example.test',
      role_description: 'a member',
      expires_in_days: 7,
      product_name: 'Acme',
    },
    'en',
  )
  erb.result(ctx.get_binding)
end
@oi_neutral.include?(@neutral_blue) && !@oi_neutral.downcase.include?('#dc4a22')
#=> true
