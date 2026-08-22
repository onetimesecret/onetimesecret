# lib/onetime/field_types/boolean_field_type.rb
#
# frozen_string_literal: true

require_relative 'coercing_field_type'

module Onetime
  module FieldTypes
    # Custom Familia field type that coerces boolean-ish values to a single
    # declared encoding on every write, and heals legacy spellings on read.
    #
    # ## Why this exists
    #
    # A plain `field :verified` accepts whatever the caller hands it, so a
    # model accumulates mixed representations across its rows: `true`,
    # `'true'`, `'1'`, `1`, `'yes'`, `nil`. Reads then have to carry the
    # burden of every spelling, and the ones that forget — `verified == true`
    # against a row stored as the string `'true'` — are silent false negatives.
    #
    # By moving coercion down to the field type we get:
    #
    # 1. **One source of truth**: every write — `obj.verified = …`,
    #    `Model.create!(verified: …)`, the fast writer `obj.verified!(…)` —
    #    funnels through {#coerce}.
    # 2. **Self-healing reads**: Familia's load path assigns through the
    #    setter, so a row persisted as `'1'` before this type existed comes
    #    back coerced. Downstream code only ever sees the declared encoding.
    # 3. **No defensive reads**: callers just use the field. No
    #    `.to_s == 'true'`, no truthy-table, no predicate wrapper whose only
    #    job is to re-do the coercion the type already did.
    #
    # ## Storage encodings
    #
    # `storage:` names how the value is persisted, using the same vocabulary
    # as the CustomDomain config models' FIELD_SPECS (#3951):
    #
    # - `:native` (**preferred for new fields**) — coerce to a real Ruby
    #   `true` / `false`. Familia JSON-encodes scalars, so these land in the
    #   datastore as the JSON literals `true` / `false` and come back as real
    #   booleans. `obj.verified` is a boolean; `if obj.verified` is correct,
    #   and it serializes to JSON as a boolean without a transform.
    #   `nil` is preserved — an unset field means "never determined", which
    #   is not the same claim as `false`.
    #
    # - `:string` (**default, grandfathered**) — coerce to the strings
    #   `'true'` / `'false'`, including `nil` → `'false'`. This is what
    #   Customer's `verified` / `suspended` already store; changing it would
    #   rewrite live rows, so it stays the default and those models keep their
    #   `verified?` / `suspended?` predicates. Do not choose it for new fields.
    #
    # ## Familia integration
    #
    # CoercingFieldType defines the generated setter and fast writer because
    # those are the Familia paths that reach scalar values. FieldType#serialize
    # and #deserialize are not used for Horreum fields. See its "Establishing
    # the pattern" section for creating a new coercing type.
    #
    # ## Usage
    #
    #   class CustomDomain < ::Familia::Horreum
    #     extend Onetime::FieldTypes::BooleanFieldMacro
    #     boolean_field :verified, storage: :native
    #   end
    #
    #   dom = CustomDomain.new
    #   dom.verified = 1        # => true
    #   dom.verified = 'YES'    # => true
    #   dom.verified = nil      # => nil (unset, not false)
    #   dom.verified!('no')     # fast writer; persists the JSON literal false
    #   dom.verified!           # reads the stored bytes
    #   dom.verified!(nil)      # also reads; it does not write false
    #
    class BooleanFieldType < CoercingFieldType
      # Canonical truthy aliases (case-insensitive). Any value whose
      # `to_s.downcase` is in this set canonicalizes to `'true'`; everything
      # else (including `nil`, `''`, `0`, `'no'`, `'false'`) becomes
      # `'false'`. Kept deliberately small — adding entries is a public
      # contract change.
      TRUTHY = %w[true 1 yes].freeze

      STORAGE_ENCODINGS = [:native, :string].freeze

      # Is this value one of the recognized spellings of true? Case
      # insensitive, and covers both the Ruby value and its string form, so
      # `true`, `'true'`, `'TRUE'`, `1`, `'1'`, `'yes'` all qualify.
      #
      # @param value [Object] anything responding to `to_s`; nil is allowed
      # @return [Boolean]
      def self.truthy?(value)
        TRUTHY.include?(value.to_s.downcase)
      end

      # Map any reasonable input to the canonical `'true'` / `'false'`
      # string form used by `storage: :string` fields.
      #
      # @param value [Object] anything responding to `to_s`; nil is allowed
      # @return [String] either `'true'` or `'false'`
      def self.canonicalize(value)
        truthy?(value) ? 'true' : 'false'
      end

      # @return [Symbol] :native or :string
      attr_reader :storage

      def initialize(name, storage: :string, **)
        unless STORAGE_ENCODINGS.include?(storage)
          raise ArgumentError,
            "Unknown boolean storage #{storage.inspect} for field #{name} " \
            "(expected one of #{STORAGE_ENCODINGS.inspect})"
        end

        @storage = storage
        super(name, **)
      end

      # Coerce an input to this field's declared encoding. Under `:native`
      # nil is preserved — an unset field means "never determined", a
      # different claim than false. `:string` keeps its grandfathered
      # nil → 'false'.
      #
      # @param value [Object]
      # @return [Boolean, String, nil]
      def coerce(value)
        return self.class.canonicalize(value) unless storage == :native

        value.nil? ? nil : self.class.truthy?(value)
      end
    end
  end
end
