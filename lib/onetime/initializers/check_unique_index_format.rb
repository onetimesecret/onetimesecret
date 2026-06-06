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
    # This check samples one entry per index. If any value is still
    # JSON-encoded it logs a warning with the remediation command.
    # Non-fatal: the app still starts so operators can run the migration.
    class CheckUniqueIndexFormat < Onetime::Boot::Initializer
      @depends_on = [:database]
      @provides   = [:unique_index_check]
      @optional   = true

      INDEX_KEYS = %w[
        custom_domain:display_domain_index
        customer:email_index
        organization:contact_email_index
        org_membership:token_lookup
      ].freeze

      def execute(_context)
        redis       = Familia.dbclient(0)
        stale_keys  = []

        INDEX_KEYS.each do |key|
          next unless redis.exists?(key)

          _cursor, entries = redis.hscan(key, '0', count: 5)
          entries.each do |_field, value|
            if value.is_a?(String) && value.start_with?('"') && value.end_with?('"')
              stale_keys << key
              break
            end
          end
        end

        return if stale_keys.empty?

        OT.boot_logger.warn "[init] #{stale_keys.size} unique_index(es) contain JSON-encoded values from pre-Familia-2.10:"
        stale_keys.each { |k| OT.boot_logger.warn "[init]   - #{k}" }
        OT.boot_logger.warn '[init] Run: bin/ots migrate migrations/2026-06-06/20260606_01_unique_index_json_to_raw --run'
        OT.boot_logger.warn '[init] Until migrated, unique_index lookups (e.g. domain SSO) may silently fail. See #3347.'
      end
    end
  end
end
