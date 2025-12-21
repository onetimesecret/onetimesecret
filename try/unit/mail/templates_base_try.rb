# try/unit/mail/templates_base_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Mail::Templates::Base class.
#
# The Base class provides:
# - Template initialization with data hash and locale
# - ERB template rendering (text and HTML)
# - Email hash generation via to_email
# - TemplateContext for clean ERB bindings with helpers

require_relative '../../support/test_helpers'

# Load the mail templates module directly without full OT boot
require 'onetime/mail/templates/base'

# Use a concrete test subclass since Base has abstract methods
class TestTemplate < Onetime::Mail::Templates::Base
  def subject
    "Test Subject from #{data[:sender]}"
  end

  def recipient_email
    data[:recipient]
  end
end

@data = { sender: 'alice@example.com', recipient: 'bob@example.com', message: 'Hello' }

# TRYOUTS

## Base class stores data hash
template = Onetime::Mail::Templates::Base.new(@data)
template.data
#=> @data

## Base class stores default locale as 'en'
template = Onetime::Mail::Templates::Base.new(@data)
template.locale
#=> 'en'

## Base class accepts custom locale
template = Onetime::Mail::Templates::Base.new(@data, locale: 'fr')
template.locale
#=> 'fr'

## Base class subject raises NotImplementedError
begin
  template = Onetime::Mail::Templates::Base.new(@data)
  template.subject
rescue NotImplementedError => e
  e.message
end
#=> "Onetime::Mail::Templates::Base must implement #subject"

## returns correct subject
template = TestTemplate.new(@data)
template.subject
#=> "Test Subject from alice@example.com"

## returns correct recipient_email
template = TestTemplate.new(@data)
template.recipient_email
#=> 'bob@example.com'

## template_name derives from class name
template = TestTemplate.new(@data)
template.send(:template_name)
#=> 'test_template'

# Note: to_email tests are in the real template tests (secret_link, welcome, etc.)
# since they require actual ERB template files to exist

## TemplateContext provides h helper for HTML escaping
context = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
context.h('<script>alert("xss")</script>')
#=> '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;'

## TemplateContext provides u helper for URL encoding
context = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
context.u('hello world')
#=> 'hello%20world'

## TemplateContext t helper returns key as placeholder (i18n stub)
context = Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en')
context.t('email.subject')
#=> 'email.subject'

## TemplateContext method_missing returns data values
context = Onetime::Mail::Templates::Base::TemplateContext.new({ name: 'Alice' }, 'en')
context.name
#=> 'Alice'

## TemplateContext method_missing handles string keys
context = Onetime::Mail::Templates::Base::TemplateContext.new({ 'name' => 'Bob' }, 'en')
context.name
#=> 'Bob'

## TemplateContext respond_to_missing? returns true for data keys
context = Onetime::Mail::Templates::Base::TemplateContext.new({ name: 'Alice' }, 'en')
context.respond_to?(:name)
#=> true

## TemplateContext respond_to_missing? returns false for unknown keys
context = Onetime::Mail::Templates::Base::TemplateContext.new({ name: 'Alice' }, 'en')
context.respond_to?(:unknown_key)
#=> false

# Note: baseuri default fallback is tested in integration tests where OT is fully loaded

## TemplateContext baseuri uses data[:baseuri] if provided
context = Onetime::Mail::Templates::Base::TemplateContext.new({ baseuri: 'https://custom.com' }, 'en')
context.baseuri
#=> 'https://custom.com'
