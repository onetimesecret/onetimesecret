# spec/unit/onetime/models/field_types/boolean_field_type_fast_writer_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit (real datastore) — BooleanFieldType fast-writer semantics
# =============================================================================
#
# BooleanFieldType wraps Familia's generated fast writer (`field!`) so the
# value it persists is coerced, not the raw argument. The wrapper has to know
# exactly which calls Familia treats as WRITES, because `field!` is
# overloaded: with no usable argument it is a READ.
#
# Verified against familia 2.12.0 (lib/familia/field_type.rb#define_fast_writer):
#
#   raise ArgumentError, "wrong number of arguments ..." if args.size > 1
#   val = args.first
#   return hget(field_name) if val.nil? || val.is_a?(Redis::Future)
#
# `[].first` and `[nil].first` are both nil, so Familia does NOT distinguish
# "no argument" from "explicit nil" — both are reads. If the wrapper coerced
# them, `storage: :string` (whose `coerce(nil)` is 'false') would turn a read
# into a silent overwrite. These examples pin that for BOTH storage encodings
# so a future Familia bump cannot change it quietly.
#
# =============================================================================

require 'spec_helper'
require 'onetime/models/field_types'

# Throwaway models rather than Customer/CustomDomain: this is about the field
# type, and each storage encoding needs its own declaration.
class BooleanFastWriterNativeModel < Familia::Horreum
  extend Onetime::Models::FieldTypes::BooleanFieldMacro

  prefix :spec_boolean_fast_writer_native
  identifier_field :probeid
  field :probeid
  boolean_field :flag, storage: :native
end

class BooleanFastWriterStringModel < Familia::Horreum
  extend Onetime::Models::FieldTypes::BooleanFieldMacro

  prefix :spec_boolean_fast_writer_string
  identifier_field :probeid
  field :probeid
  boolean_field :flag, storage: :string
end

RSpec.describe Onetime::Models::FieldTypes::BooleanFieldType do
  # Familia JSON-encodes on write, so the persisted bytes differ per encoding:
  # native booleans land as the JSON literals, strings land JSON-quoted.
  shared_examples 'a coercing fast writer' do |model:, truthy_bytes:, falsey_bytes:|
    subject(:record) { model.new(probeid: "fw-#{SecureRandom.hex(6)}") }

    def raw_bytes(record)
      record.dbclient.hget(record.dbkey, 'flag')
    end

    before do
      record.flag = true
      record.save
    end

    after { record.destroy! }

    it 'coerces a truthy write to the declared encoding' do
      record.flag!('yes')
      expect(raw_bytes(record)).to eq(truthy_bytes)
    end

    it 'coerces a falsey write to the declared encoding' do
      record.flag!('no')
      expect(raw_bytes(record)).to eq(falsey_bytes)
    end

    it 'persists false the same way an explicit false does' do
      record.flag!(false)
      expect(raw_bytes(record)).to eq(falsey_bytes)
    end

    it 'agrees byte for byte with the setter + save path' do
      record.flag!('no')
      via_fast_writer = raw_bytes(record)

      record.flag = 'no'
      record.save

      expect(via_fast_writer).to eq(raw_bytes(record))
    end

    it 'treats a bare `flag!` as a READ, returning the stored bytes untouched' do
      expect(record.flag!).to eq(truthy_bytes)
      expect(raw_bytes(record)).to eq(truthy_bytes)
    end

    it 'treats `flag!(nil)` as that same READ — familia does not distinguish it from no argument' do
      expect(record.flag!(nil)).to eq(truthy_bytes)
      expect(raw_bytes(record)).to eq(truthy_bytes)
    end

    it 'forwards an over-long argument list so familia still raises ArgumentError' do
      expect { record.flag!(true, :extra) }.to raise_error(ArgumentError, /wrong number of arguments/)
      expect(raw_bytes(record)).to eq(truthy_bytes)
    end

    it 'never coerces a Redis::Future placeholder into a write' do
      future = Redis::Future.new([:hget, 'k', 'flag'], nil, nil)

      begin
        record.flag!(future)
      rescue NoMethodError
        # familia 2.12 dereferences `val.nil?` before its own Future guard, and
        # Redis::Future subclasses BasicObject, so upstream raises here. Either
        # way the placeholder must not have been coerced and persisted.
        nil
      end

      expect(raw_bytes(record)).to eq(truthy_bytes)
    end
  end

  describe 'storage: :native' do
    it_behaves_like 'a coercing fast writer',
                    model: BooleanFastWriterNativeModel,
                    truthy_bytes: 'true',
                    falsey_bytes: 'false'

    it 'leaves an explicit nil assignment unset rather than false' do
      record = BooleanFastWriterNativeModel.new(probeid: "fw-#{SecureRandom.hex(6)}")
      record.flag = nil
      expect(record.flag).to be_nil
    end
  end

  describe 'storage: :string' do
    it_behaves_like 'a coercing fast writer',
                    model: BooleanFastWriterStringModel,
                    truthy_bytes: '"true"',
                    falsey_bytes: '"false"'

    it "coerces an assigned nil to 'false' (grandfathered encoding)" do
      record = BooleanFastWriterStringModel.new(probeid: "fw-#{SecureRandom.hex(6)}")
      record.flag = nil
      expect(record.flag).to eq('false')
    end
  end

  # The predicate that decides whether the wrapper coerces. Pure, so no
  # datastore involved — this is the contract the examples above exercise.
  describe '#fast_write?' do
    subject(:field_type) { described_class.new(:flag, storage: :native) }

    it 'is false for no arguments (familia reads)' do
      expect(field_type.fast_write?([])).to be false
    end

    it 'is false for an explicit nil (familia reads)' do
      expect(field_type.fast_write?([nil])).to be false
    end

    it 'is false for more than one argument (familia raises)' do
      expect(field_type.fast_write?([true, :extra])).to be false
    end

    it 'is false for a Redis::Future, without dereferencing it' do
      future = Redis::Future.new([:hget, 'k', 'flag'], nil, nil)
      expect(field_type.fast_write?([future])).to be false
    end

    it 'is true for a real value' do
      expect(field_type.fast_write?(['yes'])).to be true
    end

    it 'is true for an explicit false — false is a write, not an absence' do
      expect(field_type.fast_write?([false])).to be true
    end
  end
end
