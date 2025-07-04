# RSFC - Ruby Single File Components

RSFC (Ruby Single File Components) is a framework for building server-rendered components with client-side data hydration using `.rue` files. Similar to Vue.js single file components but designed for Ruby applications.

## Features

- **Server-side template rendering** with Handlebars-style syntax
- **Client-side data hydration** with secure JSON injection
- **Partial support** for component composition
- **Pluggable authentication adapters** for any auth system
- **Security-first design** with XSS protection and CSP support
- **Dependency injection** for testability and flexibility

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rsfc'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install rsfc
```

## Quick Start

### 1. Configure RSFC

```ruby
# config/initializers/rsfc.rb
RSFC.configure do |config|
  config.default_locale = 'en'
  config.template_paths = ['app/templates']
  config.features = { dark_mode: true }
  config.site_host = 'example.com'
  config.site_ssl_enabled = true
end
```

### 2. Create a .rue file

Create `app/templates/welcome.rue`:

```erb
<data>
{
  "greeting": "{{page_title}}",
  "user": {
    "name": "{{user.name}}",
    "authenticated": {{authenticated}}
  },
  "features": {{features}}
}
</data>

<template>
<div class="{{theme_class}}">
  <h1>{{page_title}}</h1>
  {{#if authenticated}}
    <p>Welcome back, {{user.name}}!</p>
  {{else}}
    <p>Please sign in to continue.</p>
  {{/if}}
  
  {{#if features.dark_mode}}
    <button onclick="toggleTheme()">Toggle Theme</button>
  {{/if}}
</div>
</template>
```

### 3. Render the component

```ruby
# In your controller or view
view = RSFC::View.new(request, session, current_user, locale)
html = view.render('welcome', page_title: 'Welcome to RSFC')
```

Or use the convenience method:

```ruby
html = RSFC.render('welcome', 
  request: request,
  session: session, 
  user: current_user,
  page_title: 'Welcome to RSFC'
)
```

## Authentication Adapters

RSFC supports pluggable authentication adapters. Implement the `RSFC::Adapters::BaseAuth` interface:

```ruby
class MyAuthAdapter < RSFC::Adapters::BaseAuth
  def initialize(user)
    @user = user
  end

  def anonymous?
    @user.nil?
  end

  def theme_preference
    @user&.theme || 'light'
  end

  def user_id
    @user&.id
  end

  def has_role?(role)
    @user&.roles&.include?(role)
  end
end

# Use with RSFC
user_adapter = MyAuthAdapter.new(current_user)
view = RSFC::View.new(request, session, user_adapter)
```

## Template Syntax

RSFC uses a Handlebars-style template syntax:

### Variables
- `{{variable}}` - HTML-escaped output
- `{{{variable}}}` - Raw output (use carefully!)

### Conditionals
```erb
{{#if condition}}
  Content when true
{{/if}}

{{#unless condition}}
  Content when false
{{/unless}}
```

### Iteration
```erb
{{#each items}}
  <div>{{name}} - {{@index}}</div>
{{/each}}
```

### Partials
```erb
{{> header}}
{{> navigation}}
```

## Data Hydration

The `<data>` section creates client-side JavaScript:

```erb
<data window="myData">
{
  "apiUrl": "{{api_base_url}}",
  "user": {{user}},
  "csrfToken": "{{csrf_token}}"
}
</data>
```

Generates:
```html
<script id="rsfc-data-abc123" type="application/json">
{"apiUrl":"https://api.example.com","user":{"id":123},"csrfToken":"token"}
</script>
<script nonce="nonce123">
window.myData = JSON.parse(document.getElementById('rsfc-data-abc123').textContent);
</script>
```

## Testing

RSFC includes comprehensive test helpers:

```ruby
# spec/spec_helper.rb
require 'rsfc'

RSFC.configure do |config|
  config.default_locale = 'en'
  config.app_environment = 'test'
  config.cache_templates = false
end

# Test context creation
context = RSFC::Context.minimal(business_data: { user: { name: 'Test' } })
expect(context.get('user.name')).to eq('Test')

# Test template rendering
template = '{{#if authenticated}}Welcome{{/if}}'
result = RSFC.render_template(template, authenticated: true)
expect(result).to eq('Welcome')
```

## Development

After checking out the repo, run:

```bash
bundle install
bundle exec rspec
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the [MIT License](https://opensource.org/licenses/MIT).