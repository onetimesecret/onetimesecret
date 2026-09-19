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
        # Scope note: this is the passive, every-pageview vector. The two
        # deliberate ones are gated to match — GET /api/v2/version and
        # GET /api/v3/version now require auth=sessionauth,basicauth — and
        # /health is network-gated to loopback/RFC1918 by
        # Onetime::Middleware::HealthAccessControl. The remaining anonymous
        # reader is the Sentry `release` field in ConfigSerializer, which the
        # SDK needs for error grouping and which only ships when the operator
        # has enabled diagnostics.
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

        serialize_snapshot_ordering(output, view_vars['snapshot_ordering'])
        output
      end

      # The three keys as declared in output_template, in one place.
      SNAPSHOT_ORDERING_KEYS = %w[snapshot_epoch snapshot_version snapshot_generated_at].freeze

      # Bootstrap snapshot ordering (ADR-046).
      #
      # OMISSION, NOT NULLS — same rule as DiagnosticsSerializer. The schema
      # validates `snapshot_epoch` and `snapshot_version` as a unit, both
      # present or both absent, and `.optional()` rejects a JSON null, which
      # would fail the WHOLE payload. So a session that is not ordered, and a
      # degraded hydration whose allocation failed, emit none of the keys.
      #
      # `snapshot_version` is passed through as the String the allocator
      # returned. It must never become a JSON number: the client compares it
      # with BigInt, beyond JavaScript's integer precision.
      #
      # `snapshot_generated_at` rides with the pair and orders nothing.
      #
      # @param output [Hash] the serializer output, mutated
      # @param ordering [Hash, nil] Onetime::SnapshotOrdering allocation
      def self.serialize_snapshot_ordering(output, ordering)
        epoch   = ordering.is_a?(Hash) ? ordering[:epoch] : nil
        version = ordering.is_a?(Hash) ? ordering[:version] : nil

        unless epoch.is_a?(String) && version.is_a?(String)
          SNAPSHOT_ORDERING_KEYS.each { |key| output.delete(key) }
          return
        end

        output['snapshot_epoch']        = epoch
        output['snapshot_version']      = version
        output['snapshot_generated_at'] = ordering[:generated_at]
        output.delete('snapshot_generated_at') if output['snapshot_generated_at'].nil?
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
            # ADR-046. Declared so SerializerRegistry passes them through;
            # .serialize deletes them again when the session is not ordered.
            'snapshot_epoch' => nil,
            'snapshot_version' => nil,
            'snapshot_generated_at' => nil,
          }
        end
      end
      SerializerRegistry.register(self)
    end
  end
end
