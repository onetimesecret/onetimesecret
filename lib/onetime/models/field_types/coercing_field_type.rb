# lib/onetime/models/field_types/coercing_field_type.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module FieldTypes
      # Base field type for values which must be normalized before storage.
      #
      # ## Naming note
      #
      # This namespace is `Onetime::Models::FieldTypes`, not `Onetime::Familia`.
      # Defining the latter shadows the top-level `::Familia` constant throughout
      # `Onetime`; `class Foo < Familia::Horreum` would then resolve the wrong
      # constant.
      #
      # Familia's scalar persistence path calls neither FieldType#serialize nor
      # FieldType#deserialize. It assigns loaded values through the generated
      # setter and persists fast writes through the generated `field!` method,
      # so these are the two paths that must coerce values.
      #
      # Invalid values are coerced to nil and logged rather than raised: a legacy
      # or corrupted stored value must not prevent the containing row from loading.
      # A later save then writes the normalized value. This does not apply to raw
      # bulk reads (HMGET/HGETALL), which bypass model loading and do not heal.
      #
      # ## Establishing the pattern
      #
      # Subclass this type to implement #coerce. Load `onetime/models/field_types`
      # before declaring a field, then extend Macros on the model or feature
      # module. The shared loader requires every concrete type used by Macros.
      class CoercingFieldType < ::Familia::FieldType
        # Coerce a value to this field type's canonical Ruby representation.
        #
        # @raise [NotImplementedError] when a subclass does not implement coercion
        def coerce(_value)
          raise NotImplementedError, "#{self.class} must implement #coerce"
        end

        # Coerce assignments before retaining their in-memory value. Familia's
        # object load path assigns through this setter, which heals legacy values.
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

        # Whether Familia will treat this fast-writer call as a write. Familia
        # uses the first argument for this decision, so both `field!` and
        # `field!(nil)` are reads. Coercing nil here would turn the latter into a
        # write for types that map nil to a stored value.
        #
        # Redis::Future subclasses BasicObject, so calling `value.nil?` can raise.
        # Use Class#=== to recognize it without dereferencing the placeholder.
        # Forwarding reads and invalid arities unchanged preserves Familia's API.
        def fast_write?(args)
          return false unless args.size == 1

          value = args.first
          return false if ::Redis::Future === value # rubocop:disable Style/CaseEquality

          !value.nil?
        end

        # Familia persists the raw fast-writer argument, bypassing the setter.
        # Wrap its generated method so every actual write reaches #coerce.
        def define_fast_writer(klass)
          super
          return unless @fast_method_name
          return unless klass.method_defined?(@fast_method_name, false)

          field_type = self
          original   = klass.instance_method(@fast_method_name)

          klass.define_method(@fast_method_name) do |*args|
            args = [field_type.coerce(args.first)] if field_type.fast_write?(args)
            original.bind_call(self, *args)
          end
        end

        protected

        # Field types are installed and frozen, so this intentionally keeps no
        # mutable state and has no record context (dbkey or identifier).
        def log_coercion_issue(value)
          preview = value.inspect[0, 50]
          Familia.warn "Invalid #{self.class.name} value for #{@name.inspect}: #{preview} (#{value.class}); coercing to nil"
        end
      end

      # Class-level declarations for all scalar coercion field types. Require the
      # relevant concrete type before declaring its field.
      module Macros
        def boolean_field(name, **)
          register_field_type(BooleanFieldType.new(name, **))
        end

        def integer_field(name, **)
          register_field_type(IntegerFieldType.new(name, **))
        end

        def float_field(name, **)
          register_field_type(FloatFieldType.new(name, **))
        end
      end

      # Compatibility name for existing models that extend BooleanFieldMacro.
      BooleanFieldMacro = Macros
    end
  end
end
