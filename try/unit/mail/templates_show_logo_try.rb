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

@welcome_data = {
  email_address: 'test@example.com',
  verification_path: 'https://example.com/verify/abc123'
}

# TRYOUTS

## show_logo? returns false when config key is absent
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
ctx.show_logo?
#=> false

## show_logo? returns false when emailer config has no show_logo key
conf_before = OT.conf['emailer']&.dup || {}
OT.conf['emailer'] ||= {}
OT.conf['emailer'].delete('show_logo')
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
result = ctx.show_logo?
OT.conf['emailer'] = conf_before
result
#=> false

## show_logo? returns false when show_logo is explicitly false
conf_before = OT.conf['emailer']&.dup || {}
OT.conf['emailer'] ||= {}
OT.conf['emailer']['show_logo'] = false
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
result = ctx.show_logo?
OT.conf['emailer'] = conf_before
result
#=> false

## show_logo? returns true when show_logo is true
conf_before = OT.conf['emailer']&.dup || {}
OT.conf['emailer'] ||= {}
OT.conf['emailer']['show_logo'] = true
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
result = ctx.show_logo?
OT.conf['emailer'] = conf_before
result
#=> true

## show_logo? returns false for string "true" (must be boolean)
conf_before = OT.conf['emailer']&.dup || {}
OT.conf['emailer'] ||= {}
OT.conf['emailer']['show_logo'] = 'true'
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
result = ctx.show_logo?
OT.conf['emailer'] = conf_before
result
#=> false

## Welcome HTML omits <img when show_logo is false
conf_before = OT.conf['emailer']&.dup || {}
OT.conf['emailer'] ||= {}
OT.conf['emailer']['show_logo'] = false
template = Onetime::Mail::Templates::Welcome.new(@welcome_data)
html = template.render_html
OT.conf['emailer'] = conf_before
html.include?('<img')
#=> false

## Welcome HTML includes <img when show_logo is true
conf_before = OT.conf['emailer']&.dup || {}
OT.conf['emailer'] ||= {}
OT.conf['emailer']['show_logo'] = true
template = Onetime::Mail::Templates::Welcome.new(@welcome_data)
html = template.render_html
OT.conf['emailer'] = conf_before
html.include?('<img')
#=> true

## Welcome HTML includes logo SVG path when show_logo is true
conf_before = OT.conf['emailer']&.dup || {}
OT.conf['emailer'] ||= {}
OT.conf['emailer']['show_logo'] = true
template = Onetime::Mail::Templates::Welcome.new(@welcome_data)
html = template.render_html
OT.conf['emailer'] = conf_before
html.include?('onetime-logo-v3-xl.svg')
#=> true
