# lib/rsfc.rb

require_relative 'rsfc/version'
require_relative 'rsfc/configuration'
require_relative 'rsfc/adapters/base_auth'
require_relative 'rsfc/adapters/base_session'
require_relative 'rsfc/context'
require_relative 'rsfc/parser'
require_relative 'rsfc/rhales'
require_relative 'rsfc/hydrator'
require_relative 'rsfc/refinements/require_refinements'
require_relative 'rsfc/view'

# Ruby Single File Components (RSFC)
#
# A framework for building server-rendered components with client-side hydration
# using .rue files (Ruby Single File Components). Similar to .vue files but for Ruby.
#
# Features:
# - Server-side template rendering with Handlebars-style syntax
# - Client-side data hydration with JSON injection
# - Partial support for component composition
# - Pluggable authentication and session adapters
# - Security-first design with XSS protection and CSP support
#
# Usage:
#   RSFC.configure do |config|
#     config.default_locale = 'en'
#     config.template_paths = ['app/templates']
#     config.features = { dark_mode: true }
#   end
#
#   view = RSFC::View.new(request, session, user)
#   html = view.render('my_component')
module RSFC
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TemplateError < Error; end
  class RenderError < Error; end

  # Convenience method to create a view with business data
  def self.render(template_name, request: nil, session: nil, user: nil, locale: nil, **business_data)
    view = View.new(request, session, user, locale, business_data: business_data)
    view.render(template_name)
  end

  # Quick template rendering for testing/simple use cases
  def self.render_template(template_content, context_data = {})
    context = Context.minimal(business_data: context_data)
    Rhales.render(template_content, context)
  end

  # Create context with business data (for advanced usage)
  def self.create_context(request: nil, session: nil, user: nil, locale: nil, **business_data)
    Context.for_view(request, session, user, locale, **business_data)
  end
end