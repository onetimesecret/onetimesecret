# apps/web/core/controllers/config_generator.rb
#
# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    # Public, unauthenticated JSON backend for the Configuration Generator
    # tool (see src/views/ConfigGenerator.vue, mounted at GET /configure).
    #
    # Deals only in YAML text — no database reads, no session, no config
    # mutation. Every request computes its response from
    # Onetime::ConfigGenerator, which is pure and stateless.
    class ConfigGenerator
      include Base

      # GET /config-generator/options
      #
      # Returns the catalog of choices (labels, descriptions, allowed values,
      # defaults) the frontend renders as form controls. Also the shape an
      # `install.sh` (or any other script) could introspect ahead of calling
      # /config-generator/render with a chosen combination.
      def options
        res['content-type'] = 'application/json'
        res.body            = JSON.generate(options: Onetime::ConfigGenerator.descriptor)
      end

      # GET /config-generator/render?deployment_mode=full&sso_enabled=true&...
      #
      # Returns the resulting etc/config.yaml / etc/auth.yaml override
      # fragments and a companion .env snippet as JSON string fields. Unknown
      # selections are ignored; invalid values fall back to that option's
      # default (see Onetime::ConfigGenerator#coerce) — the endpoint never
      # errors on a malformed query string.
      def render
        result = Onetime::ConfigGenerator.build(req.params)

        res['content-type'] = 'application/json'
        res.body            = JSON.generate(
          config_yaml: result.config_yaml,
          auth_yaml: result.auth_yaml,
          env_snippet: result.env_snippet,
          selections: result.selections,
          warnings: result.warnings,
        )
      end
    end
  end
end
