# lib/onetime/models/features/boolean_encoding.rb
#
# frozen_string_literal: true

require 'familia'

module Onetime
  module Models
    module Features
      # Tolerant boolean predicates + normalizing setters for the per-domain
      # config models (#3951).
      #
      # The seven CustomDomain config models historically disagreed on boolean
      # persistence: some fields store REAL booleans (storage :native), others
      # store 'true'/'false' STRINGS (storage :string). Writers that bypass
      # ConfigRegistry.apply_field (console sessions, create!/upsert class
      # methods) could persist the "wrong" encoding for a field, and the old
      # strict predicates (`== true`) then silently read the record as
      # disabled. This feature makes every declared boolean field tolerant on
      # READ and normalizing on WRITE, so a mixed-encoding write can no longer
      # produce a silently-disabled record — with NO data migration and no
      # rewrite of existing rows.
      #
      # Enable with +feature :boolean_encoding+ AFTER both the field
      # declarations and the FIELD_SPECS constant. For each spec entry
      # with +type: :boolean+ the feature prepends, per field:
      #
      #   - +#{field}?+  — true iff the stored value is one of
      #     true/'true'/1/'1'. Everything else — nil, '', garbage strings —
      #     reads as false (conservative default).
      #   - +#{field}=+  — nil passes through unchanged (nil means unset);
      #     any other value is normalized to the field's declared storage
      #     encoding ('true'/'false' for :string, real booleans for :native)
      #     before calling +super+ into Familia's generated writer.
      #
      # The writer is idempotent under ConfigRegistry.apply_field's
      # pre-encoding: a 'true' string arriving at a :string field stays 'true'
      # byte-for-byte, and a real boolean arriving at a :native field stays a
      # boolean, so colonel PUT stored bytes do not change.
      #
      # Familia fast writers (+field!+) bypass the prepended writer for the
      # persisted value — they hset the serialized raw input directly — so
      # bytes written via e.g. +enabled!(true)+ may be un-normalized. Read
      # tolerance covers such records; prefer +enabled=+ then +save+.
      #
      # The model's FIELD_SPECS constant is the single source of truth
      # for which fields are boolean and how each is stored; the registry's
      # load-time transcription check validates every spec'd field has a
      # setter (see ConfigRegistry).
      module BooleanEncoding
        Familia::Base.add_feature self, :boolean_encoding

        # Inputs that read and write as "set". Everything else — including
        # nil, '', and garbage strings — reads as false; on write, non-nil
        # non-truthy values normalize to the encoded false.
        TRUTHY_VALUES = [true, 'true', 1, '1'].freeze

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"

          unless base.const_defined?(:FIELD_SPECS)
            raise Familia::Problem,
              "#{base}: FIELD_SPECS must be defined before `feature :boolean_encoding`"
          end

          boolean_specs = base.const_get(:FIELD_SPECS).select do |_field, spec|
            spec[:type] == :boolean
          end

          # Fail at load for a typo'd/renamed spec field. Without this, the
          # accessors below would satisfy ConfigRegistry's method_defined?
          # transcription check for ANY spec'd boolean name, deferring the
          # failure to a runtime NoMethodError on super.
          boolean_specs.each_key do |field|
            next if base.fields.include?(field.to_sym)

            raise Familia::Problem,
              "#{base}: FIELD_SPECS declares boolean field '#{field}' " \
              'but no matching Familia field is declared'
          end

          accessors = build_accessor_module(boolean_specs)
          # Name the anonymous module so ancestors/Method#owner are readable
          # in debugging output (parens keep it an invalid constant path).
          accessors.set_temporary_name("#{base.name}::BooleanEncoding(accessors)") if base.name
          base.prepend(accessors)
        end

        # Build an anonymous module defining the tolerant predicate and
        # normalizing writer for each boolean field. The module is PREPENDED
        # (not included) so the writer can call +super+ into Familia's
        # generated setter, which owns ivar assignment and dirty tracking.
        #
        # @param boolean_specs [Hash{String => Hash}] field => spec, boolean only
        # @return [Module]
        def self.build_accessor_module(boolean_specs)
          Module.new do
            boolean_specs.each do |field, spec|
              string_storage = spec[:storage] == :string

              define_method(:"#{field}?") do
                TRUTHY_VALUES.include?(send(field))
              end

              define_method(:"#{field}=") do |value|
                if value.nil?
                  super(nil) # nil means unset — pass through, never coerce
                else
                  truthy  = TRUTHY_VALUES.include?(value)
                  encoded = if string_storage
                              truthy ? 'true' : 'false'
                            else
                              truthy
                            end
                  super(encoded)
                end
              end
            end
          end
        end
      end
    end
  end
end
