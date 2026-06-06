# lib/onetime/initializers/check_unique_index_format.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # Detects pre-Familia-2.10 JSON-encoded values in unique_index hashes.
    #
    # Familia 2.10 stores unique_index values as raw strings; older versions
    # stored them JSON-encoded (with surrounding quotes). Stale entries cause
    # lookups like CustomDomain.from_display_domain to silently return nil,
    # breaking domain-based org selection (#3347).
    #
    # Delegates to Familia.assert_indexes_current! (v2.10.1) which samples
    # raw values via HRANDFIELD and checks for legacy encoding. Non-fatal:
    # the app still starts so operators can run the migration.
    class CheckUniqueIndexFormat < Onetime::Boot::Initializer
      @depends_on = [:database]
      @provides   = [:unique_index_check]
      @optional   = true

      def execute(_context)
        unless Familia.respond_to?(:assert_indexes_current!)
          OT.boot_logger.debug '[init] Familia.assert_indexes_current! not available (requires >= 2.10.1); skipping unique_index format check'
          return
        end

        current = Familia.assert_indexes_current!(on_stale: :warn)
        return if current

        OT.boot_logger.warn '[init] Run: bin/ots migrate migrations/2026-06-06/20260606_01_unique_index_json_to_raw --run'
        OT.boot_logger.warn '[init] Until migrated, unique_index lookups (e.g. domain SSO) may silently fail. See #3347.'
      end
    end
  end
end
