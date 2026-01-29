# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Transforms::BaseTransform do
  let(:stats) { {} }
  let(:registry) { instance_double(Migration::Shared::LookupRegistry) }

  describe 'class methods' do
    describe '.requires_lookups' do
      it 'accumulates required lookup names' do
        test_class = Class.new(described_class) do
          requires_lookups :email_to_customer, :email_to_org
        end

        expect(test_class.required_lookups).to eq([:email_to_customer, :email_to_org])
      end

      it 'stores lookups for subclass without affecting parent' do
        parent_class = Class.new(described_class) do
          requires_lookups :parent_lookup
        end

        child_class = Class.new(parent_class) do
          requires_lookups :child_lookup
        end

        expect(parent_class.required_lookups).to eq([:parent_lookup])
        expect(child_class.required_lookups).to eq([:child_lookup])
      end
    end

    describe '.required_lookups' do
      it 'returns empty array by default for BaseTransform' do
        expect(described_class.required_lookups).to eq([])
      end

      it 'returns empty array for subclass without requires_lookups' do
        test_class = Class.new(described_class)
        expect(test_class.required_lookups).to eq([])
      end
    end
  end

  describe '#initialize' do
    context 'with registry' do
      it 'validates required lookups are loaded' do
        test_class = Class.new(described_class) do
          requires_lookups :email_to_customer
        end

        allow(registry).to receive(:loaded?).with(:email_to_customer).and_return(true)

        expect { test_class.new(registry: registry, stats: stats) }.not_to raise_error
      end

      it 'raises LookupValidationError when required lookup not loaded' do
        test_class = Class.new(described_class) do
          requires_lookups :email_to_customer, :email_to_org
        end

        allow(registry).to receive(:loaded?).with(:email_to_customer).and_return(true)
        allow(registry).to receive(:loaded?).with(:email_to_org).and_return(false)

        expect { test_class.new(registry: registry, stats: stats) }
          .to raise_error(
            Migration::Transforms::BaseTransform::LookupValidationError,
            /email_to_org/
          )
      end
    end

    context 'without registry' do
      it 'skips lookup validation' do
        test_class = Class.new(described_class) do
          requires_lookups :email_to_customer
        end

        expect { test_class.new(stats: stats) }.not_to raise_error
      end
    end

    it 'initializes stats as empty hash when not provided' do
      transform = described_class.new
      expect(transform.stats).to eq({})
    end

    it 'uses provided stats hash' do
      transform = described_class.new(stats: stats)
      expect(transform.stats).to be(stats)
    end
  end

  describe '#process' do
    it 'raises NotImplementedError for abstract base class' do
      transform = described_class.new(stats: stats)

      expect { transform.process({}) }
        .to raise_error(NotImplementedError, /process must be implemented/)
    end
  end

  describe '#increment_stat' do
    let(:test_class) do
      Class.new(described_class) do
        def process(record)
          increment_stat(:test_counter)
          record
        end

        def increment_multiple(key, amount)
          increment_stat(key, amount)
        end
      end
    end

    it 'tracks counters correctly' do
      transform = test_class.new(stats: stats)
      transform.process({})

      expect(stats[:test_counter]).to eq(1)
    end

    it 'accumulates multiple increments' do
      transform = test_class.new(stats: stats)
      transform.process({})
      transform.process({})
      transform.process({})

      expect(stats[:test_counter]).to eq(3)
    end

    it 'increments by specified amount' do
      transform = test_class.new(stats: stats)
      transform.increment_multiple(:bulk_counter, 5)
      transform.increment_multiple(:bulk_counter, 3)

      expect(stats[:bulk_counter]).to eq(8)
    end

    it 'initializes counter to amount on first increment' do
      transform = test_class.new(stats: stats)
      transform.increment_multiple(:new_counter, 10)

      expect(stats[:new_counter]).to eq(10)
    end
  end

  describe '#lookup' do
    let(:test_class) do
      Class.new(described_class) do
        def process(record)
          result = lookup(:email_to_customer, record[:email])
          record[:customer_id] = result
          record
        end

        def lookup_strict(name, key)
          lookup(name, key, strict: true)
        end
      end
    end

    it 'delegates to registry' do
      allow(registry).to receive(:loaded?).and_return(true)
      allow(registry).to receive(:lookup)
        .with(:email_to_customer, 'user@example.com', strict: false)
        .and_return('customer-123')

      transform = test_class.new(registry: registry, stats: stats)
      result = transform.process({ email: 'user@example.com' })

      expect(result[:customer_id]).to eq('customer-123')
    end

    it 'passes strict option through to registry' do
      allow(registry).to receive(:loaded?).and_return(true)
      allow(registry).to receive(:lookup)
        .with(:email_to_customer, 'user@example.com', strict: true)
        .and_return('customer-123')

      transform = test_class.new(registry: registry, stats: stats)
      result = transform.lookup_strict(:email_to_customer, 'user@example.com')

      expect(result).to eq('customer-123')
    end

    it 'returns nil when registry is not set' do
      transform = test_class.new(stats: stats)
      result = transform.process({ email: 'user@example.com' })

      expect(result[:customer_id]).to be_nil
    end
  end
end
