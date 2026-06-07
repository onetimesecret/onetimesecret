# lib/onetime/initializers/check_unique_index_format.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # CheckUniqueIndexFormat initializer
    #
    # Familia 2.10 changed unique_index storage from JSON-encoded strings
    # (e.g. "\"dom_abc123\"") to raw strings (e.g. "dom_abc123"). An index still
    # holding the legacy format silently breaks its generated finder: the lookup
    # returns the quoted id, Model.load finds no record, and nil is returned —
    # e.g. CustomDomain.from_display_domain, which OrganizationLoader relies on
    # for domain-based SSO selection. A deploy that skips the rebuild degrades to
    # personal-workspace fallback for every domain login, with no error.
    #
    # This boot guard samples raw values across all class-level unique indexes
    # via Familia.assert_indexes_current! and warns — non-fatally — when any are
    # still in the legacy format, pointing operators at the remediation
    # migration. Boot continues so the migration can be run.
    #
    # Remediated by:
    #   bin/ots migrate --run 20260606_01_unique_index_json_to_raw
    #
    # Refs: #3347
    class CheckUniqueIndexFormat < Onetime::Boot::Initializer
      @depends_on = [:database]
      @optional   = true

      REMEDIATION = 'bin/ots migrate --run 20260606_01_unique_index_json_to_raw'

      def execute(_context)
        # Graceful degradation: skip the check if the gem hasn't been bumped to
        # the version that ships the introspection API (Familia >= 2.10.1).
        unless Familia.respond_to?(:assert_indexes_current!)
          familia_logger.debug '[check_unique_index_format] Familia < 2.10.1; skipping unique-index format check'
          return
        end

        # on_stale: :warn samples raw values (HRANDFIELD) across every
        # class-level unique index and logs the affected coordinates without
        # aborting boot. Returns false when any index is stale.
        return if Familia.assert_indexes_current!(on_stale: :warn)

        familia_logger.warn(
          '[check_unique_index_format] Stale unique indexes detected ' \
          '(legacy Familia 2.9 JSON format). Domain-based SSO selection and ' \
          'other generated finders will silently miss until rebuilt. ' \
          "Remediate with: #{REMEDIATION}",
        )
      end
    end
  end
end
