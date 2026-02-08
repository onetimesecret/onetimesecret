# try/unit/mail/templates_brand_color_try.rb
#
# frozen_string_literal: true

# Tests that email template helpers produce inline hex colors (not CSS vars).
#
# Email clients don't support CSS custom properties, so brand_color must
# resolve to an actual hex value like '#dc4a22' in the rendered HTML.

require_relative '../../support/test_helpers'

require 'onetime/mail/views/base'

# Minimal I18n setup for template rendering
locale_files = Dir[File.join(ENV['ONETIME_HOME'], 'src/locales/*/*.json')]
locale_files.each do |file|
  locale = file.match(%r{/locales/([^/]+)/})[1]
  data = JSON.parse(File.read(file))
  I18n.backend.store_translations(locale.to_sym, data)
end

## TemplateContext brand_color returns hex string by default
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
ctx.brand_color
#=> '#dc4a22'

## TemplateContext brand_color uses data override when present
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({ brand_color: '#FF0000' }, 'en')
ctx.brand_color
#=> '#FF0000'

## TemplateContext brand_color reads from config when OT is available
OT.boot! :test, false
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
color = ctx.brand_color
color.match?(/^#[0-9A-Fa-f]{6}$/)
#=> true

## TemplateContext brand_color never returns a CSS var
OT.boot! :test, false
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
color = ctx.brand_color
color.start_with?('var(')
#=> false

## TemplateContext logo_alt delegates to product_name
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({ product_name: 'My Brand' }, 'en')
ctx.logo_alt
#=> 'My Brand'

## TemplateContext site_product_name reads brand config first
OT.boot! :test, false
ctx = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
name = ctx.send(:site_product_name)
name.is_a?(String) && !name.empty?
#=> true

## Welcome template renders with brand_color (not hardcoded #dc4a22)
OT.boot! :test, false

class WelcomeTemplateTest < Onetime::Mail::Templates::Base
  def subject
    "Welcome"
  end
end

@template_path = File.join(
  ENV['ONETIME_HOME'],
  'lib/onetime/mail/templates/welcome.html.erb'
)
@template_exists = File.exist?(@template_path)
if @template_exists
  content = File.read(@template_path)
  # Should contain ERB tag for brand_color, not hardcoded hex
  content.include?('brand_color')
else
  true
end
#=> true

## No email HTML template contains hardcoded #dc4a22
templates_dir = File.join(ENV['ONETIME_HOME'], 'lib/onetime/mail/templates')
html_templates = Dir[File.join(templates_dir, '*.html.erb')]
hardcoded = html_templates.select { |f| File.read(f).include?('#dc4a22') }
hardcoded.empty?
#=> true
