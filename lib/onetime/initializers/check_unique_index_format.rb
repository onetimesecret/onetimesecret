# lib/onetime/initializers/check_unique_index_format.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # CheckUniqueIndexFormat initializer
    #
    # Familia 2.10 changed unique_index storage from JSON-encoded strings
    # (e.g. "\"dom_abc123\"") to raw strings (e.g. "dom_abc123").
    #
    # On 2.10.0 a stale index broke its finder outright (the lookup returned the
    # quoted id, Model.load matched nothing, nil came back). On 2.10.1 the read
    # path self-heals — finders such as CustomDomain.from_display_domain resolve
    # again — but every read warns and storage stays stale until rewritten,
    # leaving the app dependent on that shim and OrganizationLoader's domain-SSO
    # selection one Familia change away from breaking.
    #
    # This boot guard delegates to Familia.assert_indexes_current!, which samples
    # raw values across CLASS-LEVEL unique indexes only. Instance-scoped indexes
    # (e.g. organization:*:email_index) cannot be sampled without a scope and are
    # NOT covered here — the migration handles those. It warns non-fatally and
    # points operators at the migration; boot continues so it can be run.
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

        # Scope note: this only covers class-level indexes. Org-scoped indexes
        # (organization:*:email_index) aren't sampled here — the migration does.
        familia_logger.warn(
          '[check_unique_index_format] Stale class-level unique indexes detected ' \
          '(legacy Familia 2.9 JSON format): finders self-heal on read but warn ' \
          'each time and storage stays stale. Org-scoped indexes are not sampled ' \
          "here; the migration covers them. Remediate with: #{REMEDIATION}",
        )
      end
    end
  end
end
