# lib/onetime/models/custom_domain/chores/normalize_boolean_encoding.rb
#
# frozen_string_literal: true

# Housekeeping chore: Rewrite drifted boolean encodings on the seven
# CustomDomain config models (#3951) to each field's DECLARED storage
# encoding.
#
# Background:
#   The config models historically disagreed on boolean persistence — some
#   fields store REAL booleans (storage :native), others 'true'/'false'
#   STRINGS (storage :string). Writers that bypassed ConfigRegistry
#   (console sessions, create!/upsert) could persist the "wrong" encoding.
#   The boolean_encoding feature makes reads tolerant and new writes
#   normalizing; this chore cleans up the bytes already stored so the raw
#   hashes converge on each model's FIELD_SPECS declaration.
#
# Raw byte shapes (Familia v2 JSON-wraps every scalar via serialize_value):
#   :native storage, canonical  ->  'true' / 'false'      (JSON booleans)
#   :string storage, canonical  ->  '"true"' / '"false"'  (JSON-quoted strings)
#
# Three branches per field, per standardize_planid:
#
#   1. raw bytes already canonical for the declared storage → silent skip
#   2. recognized divergent encoding (the other encoding's bytes, or
#      1/'1'/0/'0' variants)  → rewrite via the fast writer with the
#      canonically-typed value (field! serializes: true → 'true',
#      'true' → '"true"'), log :info with from/to
#   3. unrecognized garbage → log :info, leave alone (tolerant reads treat
#      it as false; preserve forensic evidence)
#
# nil/absent fields are skipped — nil means unset, never coerced.
# Idempotent: a second run finds only canonical bytes and does nothing.
#
# The models do not enable feature :housekeeping themselves; this file
# enables it at registration so removing the chore later (once telemetry
# confirms clean data) is a one-file deletion.
#
# Run via HousekeepingJob (one model at a time — the config models are not
# in MaintenanceJob::INSTANCE_MODELS, so the nightly all-models sweep only
# picks them up if listed under jobs.maintenance.housekeeping.models):
#   HousekeepingJob.perform('Onetime::CustomDomain::SigninConfig', :normalize_boolean_encoding)
#   bin/ots housekeeping run Onetime::CustomDomain::SigninConfig normalize_boolean_encoding

module Onetime
  module Chores
    # Constants and the shared chore body are namespaced here (rather than
    # inlined per model) because ONE implementation serves all seven config
    # models, driven by each model's FIELD_SPECS constant.
    module NormalizeBooleanEncoding
      # Raw stored bytes recognized as boolean-intent, by truth value.
      # Covers both encodings plus the numeric variants the tolerant
      # readers accept (TRUTHY_VALUES in features/boolean_encoding.rb).
      RAW_TRUTHY = ['true', '"true"', '1', '"1"'].freeze
      RAW_FALSY  = ['false', '"false"', '0', '"0"'].freeze

      # Enable feature :housekeeping (if needed) and register the chore on
      # a config model, closing over its boolean FIELD_SPECS entries.
      #
      # @param model [Class] a CustomDomain config model with FIELD_SPECS
      def self.register(model)
        boolean_specs = model.const_get(:FIELD_SPECS).select do |_field, spec|
          spec[:type] == :boolean
        end
        return if boolean_specs.empty?

        model.feature :housekeeping unless model.respond_to?(:chore)

        model.chore :normalize_boolean_encoding do |record|
          Onetime::Chores::NormalizeBooleanEncoding.run(record, boolean_specs)
        end
      end

      # Chore body: compare each spec'd boolean field's raw stored bytes
      # against the declared encoding and rewrite recognized drift.
      #
      # @param record [Familia::Horreum] the config record
      # @param boolean_specs [Hash{String => Hash}] field => spec, boolean only
      # @return [Boolean] true if any field was rewritten
      def self.run(record, boolean_specs)
        logger   = Onetime.get_logger('Chores')
        raw_hash = record.hgetall
        modified = false

        boolean_specs.each do |field, spec|
          raw = raw_hash[field]
          next if raw.nil? || raw.empty? # absent/unset — never coerce

          string_storage = spec[:storage] == :string
          canonical      = string_storage ? ['"true"', '"false"'] : %w[true false]
          next if canonical.include?(raw) # already canonical — silent skip

          truthy = RAW_TRUTHY.include?(raw)
          unless truthy || RAW_FALSY.include?(raw)
            logger.info 'Skipping unrecognized boolean bytes',
              chore: :normalize_boolean_encoding,
              model: record.class.name,
              identifier: record.identifier,
              field: field,
              raw: raw
            next
          end

          # Fast writer serializes the typed value into canonical bytes:
          #   :string -> field!('true')  stores '"true"'
          #   :native -> field!(true)    stores 'true'
          typed    = if string_storage
                    truthy ? 'true' : 'false'
                  else
                    truthy
                  end
          record.send(:"#{field}!", typed)
          modified = true

          logger.info 'Normalizing boolean encoding',
            chore: :normalize_boolean_encoding,
            model: record.class.name,
            identifier: record.identifier,
            field: field,
            from: raw,
            to: truthy ? canonical[0] : canonical[1]
        end

        modified
      end
    end
  end
end

Onetime::CustomDomain::ConfigRegistry::KINDS.each_value do |entry|
  Onetime::Chores::NormalizeBooleanEncoding.register(entry[:model])
end
