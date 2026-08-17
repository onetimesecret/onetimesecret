# lib/onetime/field_types/boolean_field_type.rb
#
# frozen_string_literal: true

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
    # against a row stored as the string `'true'` — are silent false
    # negatives.
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
    #   booleans. `obj.verified` IS a boolean; `if obj.verified` is correct,
    #   and it serializes to JSON as a boolean without a transform.
    #   `nil` is preserved — an unset field means "never determined", which
    #   is not the same claim as `false`.
    #
    # - `:string` (**default, grandfathered**) — coerce to the strings
    #   `'true'` / `'false'`, including `nil` → `'false'`. This is what
    #   Customer's `verified` / `suspended` already store; changing it would
    #   rewrite live rows, so it stays the default and those models keep
    #   their `verified?` / `suspended?` predicates. Do not choose it for new
    #   fields.
    #
    # ## Familia integration
    #
    # This mirrors the upstream `EncryptedFieldType` pattern from the
    # Familia gem (lib/familia/features/encrypted_fields/...): subclass
    # {::Familia::FieldType}, override the hooks you need, and expose a
    # class-level macro that registers an instance via
    # `register_field_type`. See {BooleanFieldMacro} for the macro.
    #
    # ## Establishing the pattern
    #
    # This is the reference implementation for adding type-level value
    # coercion to Familia models in this codebase. Future custom field
    # types (timestamp normalization, percentage clamping, enum
    # validation, …) should live alongside this one under
    # `lib/onetime/field_types/` and follow the same shape:
    #
    #   1. A `FieldType` subclass overriding {#define_setter} and
    #      {#define_fast_writer} — the two paths that actually reach the
    #      value. (Familia 2.12 declares `#serialize` / `#deserialize`
    #      hooks on FieldType but never calls them; don't rely on those.)
    #   2. A small `…Macro` module exposing a class method that wraps
    #      `register_field_type`.
    #   3. A feature module (or model directly) that does
    #      `base.extend SomeMacro` then calls the macro inline alongside
    #      regular `field` declarations.
    #
    # ## Naming note
    #
    # The enclosing module is `Onetime::FieldTypes` (not
    # `Onetime::Familia`) on purpose: nesting our code inside an
    # `Onetime::Familia` namespace would shadow the top-level `Familia`
    # constant from anywhere in the `Onetime::*` lexical scope, breaking
    # `class Foo < Familia::Horreum` lookups across the codebase.
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
    #
    class BooleanFieldType < ::Familia::FieldType
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

      # Override the setter to coerce before storing in the in-memory ivar.
      # Mirrors {::Familia::FieldType#define_setter}, interposing the
      # coercion step.
      #
      # This is also where legacy rows self-heal: Familia's load path
      # deserializes each stored value and assigns it through this setter,
      # so a row persisted as `'true'` (a JSON-quoted string) or `'1'`
      # arrives coerced, without a data migration.
      def define_setter(klass)
        field_name  = @name
        method_name = @method_name
        field_type  = self

        handle_method_conflict(klass, :"#{method_name}=") do
          klass.define_method :"#{method_name}=" do |value|
            coerced   = field_type.coerce(value)
            old_value = instance_variable_get(:"@#{field_name}")
            instance_variable_set(:"@#{field_name}", coerced)
            mark_dirty!(field_name, old_value) if respond_to?(:mark_dirty!)
          end
        end
      end

      # Familia's fast writer (`field!(value)`) assigns the ivar through the
      # setter above, but persists `serialize_value(raw_argument)` — the
      # UN-coerced input (familia/field_type.rb#define_fast_writer). That is
      # the one write path the setter cannot cover, so wrap the generated
      # method to coerce the argument before it reaches either side.
      #
      # A nil/absent argument is left alone: Familia treats `field!` with no
      # usable value as a READ, and coercing it would turn the getter into a
      # write of false.
      def define_fast_writer(klass)
        super
        return unless @fast_method_name
        return unless klass.method_defined?(@fast_method_name, false)

        field_type = self
        original   = klass.instance_method(@fast_method_name)

        klass.define_method(@fast_method_name) do |*args|
          args = [field_type.coerce(args.first)] unless args.empty? || args.first.nil?
          original.bind_call(self, *args)
        end
      end
    end

    # Class-level macro that exposes {BooleanFieldType} via a Familia-style
    # field declaration. Mirrors how upstream `encrypted_field` is added by
    # the `:encrypted_fields` feature.
    #
    # Extend this on any Familia::Horreum subclass — typically inside a
    # feature module's `included` hook — and the `boolean_field :name`
    # macro becomes available alongside the standard `field :name`.
    #
    # @example In a feature module
    #   module Status
    #     def self.included(base)
    #       base.extend Onetime::FieldTypes::BooleanFieldMacro
    #       base.boolean_field :verified
    #     end
    #   end
    #
    module BooleanFieldMacro
      # Declare a boolean-coerced field. Accepts the same options as
      # {::Familia::FieldType#initialize} (`as:`, `fast_method:`, etc.) and
      # forwards them through.
      #
      # @param name [Symbol] field name
      # @param opts [Hash] passed straight to BooleanFieldType.new
      # @return [BooleanFieldType] the registered type instance
      def boolean_field(name, **)
        register_field_type(BooleanFieldType.new(name, **))
      end
    end
  end
end
