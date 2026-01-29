# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Migration::Destinations::LookupDestination do
  include TempDirHelper
  include JsonlFileHelper

  let(:temp_dir) { create_temp_dir }
  let(:output_file) { File.join(temp_dir, 'lookups', 'test_lookup.json') }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe '#initialize' do
    it 'creates output directory if missing' do
      expect(Dir.exist?(File.dirname(output_file))).to be false

      described_class.new(file: output_file, key_field: :email, value_field: :objid)

      expect(Dir.exist?(File.dirname(output_file))).to be true
    end

    it 'sets attributes correctly' do
      dest = described_class.new(
        file: output_file,
        key_field: :email,
        value_field: :objid,
        phase: 2
      )

      expect(dest.file).to eq(output_file)
      expect(dest.key_field).to eq(:email)
      expect(dest.value_field).to eq(:objid)
      expect(dest.phase).to eq(2)
      expect(dest.count).to eq(0)
    end

    it 'converts string field names to symbols' do
      dest = described_class.new(
        file: output_file,
        key_field: 'email',
        value_field: 'objid'
      )

      expect(dest.key_field).to eq(:email)
      expect(dest.value_field).to eq(:objid)
    end

    it 'defaults phase to 1' do
      dest = described_class.new(file: output_file, key_field: :email, value_field: :objid)
      expect(dest.phase).to eq(1)
    end
  end

  describe '#write' do
    describe 'key extraction precedence' do
      context 'key at top-level' do
        it 'extracts key from top-level record field' do
          dest = described_class.new(file: output_file, key_field: :email, value_field: :objid)

          dest.write({ email: 'test@example.com', objid: 'uuid-123' })
          dest.close

          data = read_json(output_file)
          expect(data).to eq({ 'test@example.com' => 'uuid-123' })
        end
      end

      context 'key in v2_fields' do
        it 'extracts key from :v2_fields if not at top level' do
          dest = described_class.new(file: output_file, key_field: :email, value_field: :objid)

          dest.write({
            key: 'customer:uuid:object',
            v2_fields: { 'email' => 'from_v2@example.com', 'objid' => 'v2-uuid' },
          })
          dest.close

          data = read_json(output_file)
          expect(data).to eq({ 'from_v2@example.com' => 'v2-uuid' })
        end
      end

      context 'key in fields (fallback)' do
        it 'extracts key from :fields as fallback' do
          dest = described_class.new(file: output_file, key_field: :custid, value_field: :plan)

          dest.write({
            key: 'customer:test:object',
            fields: { 'custid' => 'user@example.com', 'plan' => 'pro' },
          })
          dest.close

          data = read_json(output_file)
          expect(data).to eq({ 'user@example.com' => 'pro' })
        end
      end

      context 'precedence order' do
        it 'prefers top-level over v2_fields over fields' do
          dest = described_class.new(file: output_file, key_field: :email, value_field: :objid)

          # Record has all three sources
          dest.write({
            email: 'top@example.com',
            objid: 'top-uuid',
            v2_fields: { 'email' => 'v2@example.com', 'objid' => 'v2-uuid' },
            fields: { 'email' => 'fields@example.com', 'objid' => 'fields-uuid' },
          })
          dest.close

          data = read_json(output_file)
          expect(data).to eq({ 'top@example.com' => 'top-uuid' })
        end
      end
    end

    describe 'value extraction' do
      it 'follows same precedence for value extraction' do
        dest = described_class.new(file: output_file, key_field: :email, value_field: :objid)

        # Key from v2_fields, value from top-level
        dest.write({
          objid: 'top-objid',
          v2_fields: { 'email' => 'v2@example.com' },
        })
        dest.close

        data = read_json(output_file)
        expect(data).to eq({ 'v2@example.com' => 'top-objid' })
      end
    end

    describe 'skipping invalid records' do
      let(:dest) { described_class.new(file: output_file, key_field: :email, value_field: :objid) }

      after { dest.close }

      it 'skips records with missing key' do
        dest.write({ objid: 'uuid-123' }) # no email
        dest.close

        expect(File.exist?(output_file)).to be false
        expect(dest.count).to eq(0)
      end

      it 'skips records with nil key' do
        dest.write({ email: nil, objid: 'uuid-123' })
        dest.close

        expect(File.exist?(output_file)).to be false
        expect(dest.count).to eq(0)
      end

      it 'skips records with empty string key' do
        dest.write({ email: '', objid: 'uuid-123' })
        dest.close

        expect(File.exist?(output_file)).to be false
        expect(dest.count).to eq(0)
      end

      it 'skips records with missing value' do
        dest.write({ email: 'test@example.com' }) # no objid
        dest.close

        expect(File.exist?(output_file)).to be false
        expect(dest.count).to eq(0)
      end

      it 'skips records with nil value' do
        dest.write({ email: 'test@example.com', objid: nil })
        dest.close

        expect(File.exist?(output_file)).to be false
        expect(dest.count).to eq(0)
      end

      it 'skips records with empty string value' do
        dest.write({ email: 'test@example.com', objid: '' })
        dest.close

        expect(File.exist?(output_file)).to be false
        expect(dest.count).to eq(0)
      end

      it 'skips nil records' do
        dest.write(nil)
        dest.close

        expect(File.exist?(output_file)).to be false
        expect(dest.count).to eq(0)
      end
    end

    describe 'multiple values for same key' do
      it 'last write wins' do
        dest = described_class.new(file: output_file, key_field: :email, value_field: :objid)

        dest.write({ email: 'same@example.com', objid: 'first-uuid' })
        dest.write({ email: 'same@example.com', objid: 'second-uuid' })
        dest.write({ email: 'same@example.com', objid: 'third-uuid' })
        dest.close

        data = read_json(output_file)
        expect(data).to eq({ 'same@example.com' => 'third-uuid' })
        # Count should be 3 (counts each write)
        expect(dest.count).to eq(3)
      end
    end

    describe 'count tracking' do
      it 'increments count for each valid write' do
        dest = described_class.new(file: output_file, key_field: :email, value_field: :objid)

        dest.write({ email: 'a@test.com', objid: 'uuid-1' })
        dest.write({ email: 'b@test.com', objid: 'uuid-2' })
        dest.write({ email: '', objid: 'uuid-3' }) # skipped
        dest.write({ email: 'c@test.com', objid: 'uuid-3' })
        dest.close

        expect(dest.count).to eq(3)
      end
    end
  end

  describe '#close' do
    context 'with data' do
      it 'writes pretty JSON on close' do
        dest = described_class.new(file: output_file, key_field: :email, value_field: :objid)

        dest.write({ email: 'test@example.com', objid: 'uuid-123' })
        dest.close

        content = File.read(output_file)
        # Pretty JSON has newlines
        expect(content).to include("\n")
        # Parseable
        expect(JSON.parse(content)).to eq({ 'test@example.com' => 'uuid-123' })
      end
    end

    context 'with empty data' do
      it 'does not write file when no valid records' do
        dest = described_class.new(file: output_file, key_field: :email, value_field: :objid)
        dest.close

        expect(File.exist?(output_file)).to be false
      end
    end

    context 'with registry' do
      it 'updates registry if registry provided' do
        registry = Migration::Shared::LookupRegistry.new(exports_dir: temp_dir)

        dest = described_class.new(
          file: output_file,
          key_field: :email,
          value_field: :objid,
          registry: registry,
          lookup_name: :email_to_customer,
          phase: 1
        )

        dest.write({ email: 'test@example.com', objid: 'uuid-123' })
        dest.close

        expect(registry.loaded?(:email_to_customer)).to be true
        expect(registry.lookup(:email_to_customer, 'test@example.com')).to eq('uuid-123')
      end

      it 'does not update registry without lookup_name' do
        registry = Migration::Shared::LookupRegistry.new(exports_dir: temp_dir)

        dest = described_class.new(
          file: output_file,
          key_field: :email,
          value_field: :objid,
          registry: registry
          # no lookup_name
        )

        dest.write({ email: 'test@example.com', objid: 'uuid-123' })
        dest.close

        expect(registry.loaded?(:email_to_customer)).to be false
      end
    end

    context 'with stats' do
      it 'updates stats :lookup_entries count' do
        stats = { lookup_entries: 0 }

        dest = described_class.new(
          file: output_file,
          key_field: :email,
          value_field: :objid,
          stats: stats
        )

        dest.write({ email: 'a@test.com', objid: 'uuid-1' })
        dest.write({ email: 'b@test.com', objid: 'uuid-2' })
        dest.write({ email: 'c@test.com', objid: 'uuid-3' })
        dest.close

        expect(stats[:lookup_entries]).to eq(3)
      end

      it 'does not update stats when no data' do
        stats = { lookup_entries: 99 }

        dest = described_class.new(
          file: output_file,
          key_field: :email,
          value_field: :objid,
          stats: stats
        )
        dest.close

        # Stats unchanged because close returns early
        expect(stats[:lookup_entries]).to eq(99)
      end
    end
  end

  describe 'type coercion' do
    it 'converts string keys and values to strings in output' do
      dest = described_class.new(file: output_file, key_field: :id, value_field: :name)

      dest.write({ id: 'user-123', name: 'Alice' })
      dest.close

      data = read_json(output_file)
      expect(data).to eq({ 'user-123' => 'Alice' })
    end

    it 'requires string-like values that respond to empty?' do
      # Note: The implementation calls .empty? on key/value before conversion,
      # so non-string types like Integer will raise NoMethodError.
      # This test documents this limitation.
      dest = described_class.new(file: output_file, key_field: :id, value_field: :count)

      expect {
        dest.write({ id: 123, count: 456 })
      }.to raise_error(NoMethodError, /empty\?/)
    end
  end
end
