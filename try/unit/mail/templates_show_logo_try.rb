# try/unit/mail/templates_show_logo_try.rb
#
# frozen_string_literal: true

# Tests for the show_logo? toggle on TemplateContext.
#
# The email <img> is gated on `show_logo? && logo_url` (layout.html.erb).
# show_logo? defaults to false (EMAILER_SHOW_LOGO unset) — the logo renders
# only when the operator opts in AND a logo_url is configured. With show_logo
# false/absent, or with no logo_url, the <img> is omitted to avoid broken
# images on air-gapped networks.

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'onetime/mail'

# Helper: mutate emailer.show_logo, yield, restore.
# Also clears brand.logo_url so logo-absent tests are config-independent.
def with_show_logo(value, logo_url: nil)
  conf_before = OT.conf['emailer']&.dup || {}
  brand_before = OT.conf['brand']&.dup || {}
  OT.conf['emailer'] ||= {}
  OT.conf['brand'] ||= {}
  if value == :absent
    OT.conf['emailer'].delete('show_logo')
  else
    OT.conf['emailer']['show_logo'] = value
  end
  OT.conf['brand']['logo_url'] = logo_url
  result = yield
  OT.conf['emailer'] = conf_before
  OT.conf['brand'] = brand_before
  result
end

@welcome_data = {
  email_address: 'test@example.com',
  verification_path: 'https://example.com/verify/abc123'
}

# TRYOUTS

## show_logo? returns false when config key is absent
with_show_logo(:absent) do
  ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
  ctx.show_logo?
end
#=> false

## show_logo? returns false when show_logo is nil
with_show_logo(nil) do
  ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
  ctx.show_logo?
end
#=> false

## show_logo? returns false when show_logo is explicitly false
with_show_logo(false) do
  ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
  ctx.show_logo?
end
#=> false

## show_logo? returns true when show_logo is exactly true
with_show_logo(true) do
  ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
  ctx.show_logo?
end
#=> true

## show_logo? returns false for string "true" (must be boolean)
with_show_logo('true') do
  ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
  ctx.show_logo?
end
#=> false

## Welcome HTML omits <img when show_logo is false
with_show_logo(false) do
  template = Onetime::Mail::Templates::Welcome.new(@welcome_data)
  template.render_html.include?('<img')
end
#=> false

## Welcome HTML omits <img when show_logo is true but no logo_url configured
# Layout guard is `show_logo? && logo_url`, so show_logo alone is insufficient.
with_show_logo(true) do
  template = Onetime::Mail::Templates::Welcome.new(@welcome_data)
  template.render_html.include?('<img')
end
#=> false

## Welcome HTML omits onetime-logo SVG when no logo_url configured (#3049 neutralization)
with_show_logo(true) do
  template = Onetime::Mail::Templates::Welcome.new(@welcome_data)
  template.render_html.include?('onetime-logo-v3-xl.svg')
end
#=> false
