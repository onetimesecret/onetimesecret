# try/unit/mail/templates_show_logo_try.rb
#
# frozen_string_literal: true

# Tests for the show_logo? toggle on TemplateContext.
#
# When emailer.show_logo is true, HTML emails include the logo <img>.
# When false/absent, the <img> is omitted to avoid broken images on
# air-gapped networks.

require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'onetime/mail'

# Helper: mutate emailer.show_logo, yield, restore.
def with_show_logo(value)
  conf_before = OT.conf['emailer']&.dup || {}
  OT.conf['emailer'] ||= {}
  if value == :absent
    OT.conf['emailer'].delete('show_logo')
  else
    OT.conf['emailer']['show_logo'] = value
  end
  result = yield
  OT.conf['emailer'] = conf_before
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
# Layout guard is now logo_url (not show_logo?), so show_logo alone is insufficient.
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
