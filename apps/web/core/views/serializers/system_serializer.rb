# apps/web/core/views/serializers/system_serializer.rb
#
# frozen_string_literal: true

module Core
  module Views
    # Serializes system-level information for the frontend
    #
    # Responsible for transforming application version, runtime information,
    # and security-related values for frontend consumption.
    module SystemSerializer
      # Emitted in place of version details for anonymous visitors.
      #
      # Deliberately an empty string rather than nil: the frontend types these
      # as `z.string().default('')` (src/schemas/contracts/bootstrap.ts), and
      # Zod's .default() only fills `undefined` — a JSON null fails validation
      # and would reject the entire bootstrap payload. An empty string also
      # keeps the keys present, preserving the serializer field contract that
      # both the Ruby and TypeScript contract tests assert.
      WITHHELD = ''

      # Serializes system data from view variables
      #
      # @param view_vars [Hash] The view variables containing system information
      # @return [Hash] Serialized system data including version and security values
      def self.serialize(view_vars)
        output = output_template

        # Version and runtime details are withheld from anonymous visitors.
        # The exact app-version/Ruby-version pairing is the primary input to
        # fingerprinting an install and matching it against known CVEs, and it
        # was previously emitted to every visitor on every page load. Signed-in
        # sessions still receive it (footer display, support diagnostics).
        #
        # Scope note: ruby_version is not exposed anywhere else, so this closes
        # its disclosure outright. The app version remains available to
        # unauthenticated callers via GET /api/v2/version and GET /api/v3/version,
        # which are deliberate public meta endpoints (see the "Meta/Public
        # endpoints" block in apps/api/v3/routes.txt). What changes here is the
        # passive, every-pageview disclosure — retrieving the version now takes
        # a deliberate request to an endpoint an operator can choose to remove.
        # (/health also reports it but is network-gated to loopback/RFC1918 by
        # Onetime::Middleware::HealthAccessControl, so it is not public.)
        if view_vars['authenticated']
          output['ot_version']      = OT::VERSION.to_s
          output['ot_version_long'] = OT::VERSION.details
          output['ruby_version']    = RUBY_VERSION.to_s
        else
          output['ot_version']      = WITHHELD
          output['ot_version_long'] = WITHHELD
          output['ruby_version']    = WITHHELD
        end

        output['shrimp'] = view_vars['shrimp']
        output['nonce']  = view_vars['nonce']
        output
      end

      class << self
        # Provides the base template for system serializer output
        #
        # @return [Hash] Template with all possible system output fields
        def output_template
          {
            'ot_version' => nil,
            'ot_version_long' => nil,
            'ruby_version' => nil,
            'shrimp' => nil,
            'nonce' => nil,
          }
        end
      end
      SerializerRegistry.register(self)
    end
  end
end
