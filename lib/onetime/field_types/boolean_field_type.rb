# lib/onetime/field_types/boolean_field_type.rb
#
# frozen_string_literal: true

module Onetime
  module FieldTypes
    # Custom Familia field type that stores boolean-ish values in a canonical
    # 'true' / 'false' string form, regardless of how callers express truth.
    #
    # ## Why this exists
    #
    # Familia's hash fields are persisted to Redis as strings, so storing
    # native Ruby booleans is a category error — they round-trip as whatever
    # string the redis client picks (`"true"`, `"1"`, etc., depending on the
    # call path). Codebases that lean on `field :verified` end up with
    # mixed representations: `'true'`, `'false'`, `'1'`, `'0'`, sometimes
    # raw booleans in memory, and predicate methods like `verified?` end up
    # carrying the burden of every possible spelling.
    #
    # By moving canonicalization down to the field type itself we get:
    #
    # 1. **One source of truth**: every write — `cust.verified = …`,
    #    `Customer.create!(verified: …)`, the fast writer
    #    `cust.verified!(…)` — funnels through {.canonicalize}.
    # 2. **Self-healing reads**: legacy values like `'1'` written before
    #    this type existed are normalized when loaded from Redis, so
    #    downstream code only ever sees `'true'` or `'false'`.
    # 3. **Predicate simplicity**: `def verified? = verified == 'true'`.
    #    No `to_s.downcase`, no truthy-table.
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
    #   1. A `FieldType` subclass overriding {#define_setter},
    #      {#serialize}, and {#deserialize} as appropriate.
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
    #   class Customer < ::Familia::Horreum
    #     extend Onetime::FieldTypes::BooleanFieldMacro
    #     boolean_field :verified
    #   end
    #
    #   cust = Customer.new
    #   cust.verified = 1       # in-memory: 'true'
    #   cust.verified           # => 'true'
    #   cust.verified = 'YES'   # in-memory: 'true'
    #   cust.verified!('no')    # fast writer; persists 'false' to Redis
    #
    class BooleanFieldType < ::Familia::FieldType
      # Canonical truthy aliases (case-insensitive). Any value whose
      # `to_s.downcase` is in this set canonicalizes to `'true'`; everything
      # else (including `nil`, `''`, `0`, `'no'`, `'false'`) becomes
      # `'false'`. Kept deliberately small — adding entries is a public
      # contract change.
      TRUTHY = %w[true 1 yes].freeze

      # Map any reasonable input to the canonical `'true'` / `'false'`
      # string form. Class-level so it can be referenced from tests and
      # from the closures defined inside {#define_setter} without holding
      # a reference to `self`.
      #
      # @param value [Object] anything responding to `to_s`; nil is allowed
      # @return [String] either `'true'` or `'false'`
      def self.canonicalize(value)
        TRUTHY.include?(value.to_s.downcase) ? 'true' : 'false'
      end

      # Override the setter to canonicalize before storing in the
      # in-memory ivar. Mirrors {::Familia::FieldType#define_setter},
      # interposing a coercion step so that subsequent reads of the raw
      # field via `instance_variable_get` already see the canonical form.
      def define_setter(klass)
        field_name  = @name
        method_name = @method_name

        handle_method_conflict(klass, :"#{method_name}=") do
          klass.define_method :"#{method_name}=" do |value|
            canonical = BooleanFieldType.canonicalize(value)
            old_value = instance_variable_get(:"@#{field_name}")
            instance_variable_set(:"@#{field_name}", canonical)
            mark_dirty!(field_name, old_value) if respond_to?(:mark_dirty!)
          end
        end
      end

      # Database serialization hook. Even though {#define_setter} already
      # canonicalizes on the in-memory side, the fast writer
      # (`field!(value)`) and any future Familia code path that calls
      # `serialize_value` directly bypass the setter — so we canonicalize
      # here too. Belt and suspenders against gem refactors.
      def serialize(value, _record = nil)
        BooleanFieldType.canonicalize(value)
      end

      # Database deserialization hook. Loaded values pass through here
      # before being assigned to the in-memory ivar, so this is where
      # legacy data self-heals: rows persisted as `'1'` / `'0'` (or any
      # other historical spelling) come back as `'true'` / `'false'`.
      def deserialize(value, _record = nil)
        BooleanFieldType.canonicalize(value)
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
      def boolean_field(name, **opts)
        register_field_type(BooleanFieldType.new(name, **opts))
      end
    end
  end
end
