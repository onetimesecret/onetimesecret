# apps/web/manifold/application.rb

require 'rhales'

require_relative '../../base_application'

require_relative 'controllers'

# TODO: Rename. UI? Spigot? Manifold? Pylon? Ferrule? Abutment? Rootstock?
module Manifold
  class Application < ::BaseApplication
    @uri_prefix = '/'.freeze

    # Common middleware stack
    use Rack::ClearSessionMessages
    use Rack::DetectHost

    # Applications middleware stack
    use Onetime::DomainStrategy

    warmup do
      # Expensive initialization tasks go here

      # Configure Rhales with CSP and manifold-specific settings
      Rhales.configure do |config|
        config.template_paths  = [File.join(Onetime::HOME, 'templates', 'web')]
        config.cache_templates = false
        config.default_locale  = 'en'

        config.hydration.injection_strategy = :early
        # config.hydration.fallback_to_late = true # injects at the end of the document
        # config.hydration.mount_point_selectors = ['#app', '#root', '[data-mount]']

        # CSP configuration for security by default
        config.csp_enabled = true
        config.auto_nonce = true
        config.nonce_header_name = 'ots.nonce'

        # Custom CSP policy for onetimesecret
        config.csp_policy = {
          'default-src' => ["'self'"],
          'script-src' => ["'self'", "'nonce-{{nonce}}'"],
          'style-src' => ["'self'", "'nonce-{{nonce}}'", "'unsafe-hashes'"],
          'img-src' => ["'self'", 'data:', 'https:'],
          'font-src' => ["'self'", 'https:'],
          'connect-src' => ["'self'"],
          'base-uri' => ["'self'"],
          'form-action' => ["'self'"],
          'frame-ancestors' => ["'none'"],
          'object-src' => ["'none'"],
          'upgrade-insecure-requests' => [],
        }
      end

      # Log warmup completion
      Onetime.li 'Manifold warmup completed'
    end

    protected

    def build_router
      routes_path = File.join(Onetime::HOME, 'apps/web/manifold/routes')
      router      = Otto.new(routes_path)

      # Default error responses
      headers             = { 'Content-Type' => 'text/html' }
      router.not_found    = [404, headers, ['Not Found']]
      router.server_error = [500, headers, ['Internal Server Error']]

      router
    end
  end
end
