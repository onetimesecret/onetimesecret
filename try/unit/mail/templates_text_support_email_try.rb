# try/unit/mail/templates_text_support_email_try.rb
#
# frozen_string_literal: true

#
# BRAND_SUPPORT_EMAIL in the plaintext email path (issue #3362)
#
# Before #3362, render_text used no shared layout, so the support contact
# (BRAND_SUPPORT_EMAIL) was wired into the HTML footer only — plaintext and
# multipart-fallback emails omitted it. The fix consolidates the text footer
# into a shared layout (lib/onetime/mail/templates/layout.txt.erb) that
# render_text now wraps content in, mirroring render_html. The layout carries
# a conditional support line.
#
# Critical assertions:
#   - support_email (from brand conf) appears in the wrapped text output.
#   - When support_email is nil, the support line is absent and the email
#     still renders (body content preserved).
#   - The consolidated footer (--/product_name/baseuri) appears exactly once
#     (no double footer from leftover per-template footers).
#   - A real subclass (SecretLink) renders through render_text end-to-end and
#     picks up the support line.
#   - feedback_email is excluded from wrapping: its own footer stays, and it
#     gets no support line (operator-facing notification).
#
# NOTE: in the tryouts test env, generated/locales/ is unpopulated, so t()
# returns a "Translation missing: ..." string rather than the translated
# label. Assertions therefore target the support_email *address value* (which
# is config-sourced and deterministic), never the translated "Support" label.
#

require_relative '../../support/test_helpers'

# Boot to populate OT.conf for the support_email fallback chain.
OT.boot! :test, false

require 'onetime/mail'

@base_class = Onetime::Mail::Templates::Base

# Helper: run a block with OT.conf['brand'] set to brand_hash, then restore.
def with_brand_conf(brand_hash)
  saved     = YAML.load(YAML.dump(OT.conf))
  conf_copy = YAML.load(YAML.dump(saved))
  conf_copy['brand'] = brand_hash
  OT.send(:conf=, conf_copy)
  yield
ensure
  OT.send(:conf=, saved) rescue nil
end

# Helper: run a block with OT.conf['brand'] removed entirely, then restore.
def without_brand_conf
  saved     = YAML.load(YAML.dump(OT.conf))
  conf_copy = YAML.load(YAML.dump(saved))
  conf_copy.delete('brand')
  OT.send(:conf=, conf_copy)
  yield
ensure
  OT.send(:conf=, saved) rescue nil
end

# Valid SecretLink data (mirrors templates_secret_link_try.rb).
@secret_link_data = {
  secret_key: 'abc123def456',
  share_domain: nil,
  recipient: 'recipient@example.com',
  sender_email: 'sender@example.com',
}

# TRYOUTS

# ============================================================================
# Shared text layout: support_email present / absent (via wrap_in_layout)
# ============================================================================

## [configured] support_email address appears in the wrapped text output
with_brand_conf({ 'support_email' => 'help@acme.test' }) do
  base = @base_class.new({}, locale: 'en')
  out  = base.send(:wrap_in_layout, 'BODY', 'txt')
  out.include?('help@acme.test')
end
#=> true

## [configured] the wrapped output still includes the body content
with_brand_conf({ 'support_email' => 'help@acme.test' }) do
  base = @base_class.new({}, locale: 'en')
  out  = base.send(:wrap_in_layout, 'BODY', 'txt')
  out.include?('BODY')
end
#=> true

## [unconfigured] no support line is rendered when support_email is nil
without_brand_conf do
  base = @base_class.new({}, locale: 'en')
  out  = base.send(:wrap_in_layout, 'BODY', 'txt')
  # No literal address and no 'Support:' style line; body still present.
  !out.include?('help@acme.test') && out.include?('BODY')
end
#=> true

## [unconfigured] email still renders a footer (product/baseuri) without support
without_brand_conf do
  base = @base_class.new({ product_name: 'Acme', baseuri: 'https://acme.test' }, locale: 'en')
  out  = base.send(:wrap_in_layout, 'BODY', 'txt')
  out.include?('Acme') && out.include?('https://acme.test')
end
#=> true

# ============================================================================
# No double footer — the '--' separator appears exactly once
# ============================================================================

## the consolidated '--' footer separator appears exactly once (configured)
with_brand_conf({ 'support_email' => 'help@acme.test' }) do
  base = @base_class.new({}, locale: 'en')
  out  = base.send(:wrap_in_layout, 'BODY', 'txt')
  out.scan(/^--$/).size
end
#=> 1

## the consolidated '--' footer separator appears exactly once (unconfigured)
without_brand_conf do
  base = @base_class.new({}, locale: 'en')
  out  = base.send(:wrap_in_layout, 'BODY', 'txt')
  out.scan(/^--$/).size
end
#=> 1

# ============================================================================
# End-to-end: a real subclass renders through render_text
# ============================================================================

## [configured] SecretLink#render_text includes the support address
with_brand_conf({ 'support_email' => 'help@acme.test' }) do
  tmpl = Onetime::Mail::Templates::SecretLink.new(@secret_link_data)
  tmpl.render_text.include?('help@acme.test')
end
#=> true

## [configured] SecretLink#render_text footer separator appears exactly once
with_brand_conf({ 'support_email' => 'help@acme.test' }) do
  tmpl = Onetime::Mail::Templates::SecretLink.new(@secret_link_data)
  tmpl.render_text.scan(/^--$/).size
end
#=> 1

## [unconfigured] SecretLink#render_text omits support line but still renders body
without_brand_conf do
  tmpl = Onetime::Mail::Templates::SecretLink.new(@secret_link_data)
  out  = tmpl.render_text
  !out.include?('help@acme.test') && out.include?('/secret/abc123def456')
end
#=> true

# ============================================================================
# feedback_email exclusion — keeps its own footer, gets no support line
# ============================================================================

## [exclusion] FeedbackEmail opts out of the shared text layout
Onetime::Mail::Templates::FeedbackEmail.text_layout?
#=> false

## [exclusion] wrapped templates (SecretLink) default to the shared text layout
Onetime::Mail::Templates::SecretLink.text_layout?
#=> true

## [exclusion] FeedbackEmail#render_text gets no support line even when configured
with_brand_conf({ 'support_email' => 'help@acme.test' }) do
  tmpl = Onetime::Mail::Templates::FeedbackEmail.new({
    recipient_email: 'admin@example.com',
    email_address: 'user@example.com',
    display_domain: 'example.com',
    user_id: 'cust-1',
    message: 'Hello there',
  })
  tmpl.render_text.include?('help@acme.test')
end
#=> false

# ============================================================================
# Static dedup proof — per-template footers stripped, layout owns the footer
# ============================================================================

## none of the 11 wrapped text templates still carry the stripped footer block
home    = ENV.fetch('ONETIME_HOME')
wrapped = %w[
  email_change_confirmation email_change_requested email_changed
  expiration_warning incoming_secret magic_link organization_invitation
  password_request secret_link secret_revealed welcome
]
block = "--\n<%= product_name %>\n<%= baseuri %>"
offenders = wrapped.select do |name|
  File.read(File.join(home, 'lib/onetime/mail/templates', "#{name}.txt.erb")).include?(block)
end
offenders
#=> []

## layout.txt.erb contains the consolidated footer block exactly once
home   = ENV.fetch('ONETIME_HOME')
layout = File.read(File.join(home, 'lib/onetime/mail/templates/layout.txt.erb'))
layout.scan("--\n<%= product_name %>\n<%= baseuri %>").size
#=> 1

## layout.txt.erb gates the support line on support_email
home   = ENV.fetch('ONETIME_HOME')
layout = File.read(File.join(home, 'lib/onetime/mail/templates/layout.txt.erb'))
layout.include?('if support_email') && layout.include?("email.common.support_label")
#=> true

## feedback_email.txt.erb is left untouched — still carries its own signature footer
home = ENV.fetch('ONETIME_HOME')
src  = File.read(File.join(home, 'lib/onetime/mail/templates/feedback_email.txt.erb'))
src.include?("email.feedback_email.signature")
#=> true
