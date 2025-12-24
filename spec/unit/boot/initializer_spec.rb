# spec/unit/boot/initializer_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for base Initializer class
# Tests focus on @phase infrastructure and instance method delegation
RSpec.describe Onetime::Boot::Initializer do
  # Helper to create clean test classes
  # Each test gets a fresh class to avoid pollution
  # Always includes cleanup/reconnect methods so fork_sensitive classes pass validation
  def new_test_class(name = nil, &block)
    Class.new(described_class) do
      define_singleton_method(:name) { name || "TestInitializer#{object_id}" }
      def execute(_context)
        # Default no-op implementation
      end
      # Required for fork_sensitive initializers - safe no-ops for all phases
      def cleanup; end
      def reconnect; end
      class_eval(&block) if block_given?
    end
  end

  describe '.phase class variable' do
    context 'default phase value' do
      it 'defaults to :preload when not set' do
        klass = new_test_class
        expect(klass.phase).to eq(:preload)
      end

      it 'returns :preload for instance when class has no custom phase' do
        klass = new_test_class
        instance = klass.new
        expect(instance.phase).to eq(:preload)
      end
    end

    context 'custom phase value' do
      it 'stores :fork_sensitive when explicitly set' do
        klass = new_test_class do
          @phase = :fork_sensitive
        end
        expect(klass.phase).to eq(:fork_sensitive)
      end

      it 'returns custom phase via instance method delegation' do
        klass = new_test_class do
          @phase = :fork_sensitive
        end
        instance = klass.new
        expect(instance.phase).to eq(:fork_sensitive)
      end
    end

    context 'phase inheritance' do
      it 'inherits default phase from parent class' do
        parent = new_test_class
        child = Class.new(parent)
        expect(child.phase).to eq(:preload)
      end

      it 'inherits custom phase from parent class' do
        parent = new_test_class do
          @phase = :fork_sensitive
        end
        child = Class.new(parent)
        # Note: Ruby class instance variables are NOT inherited by default
        # So child.phase will fall back to default :preload unless explicitly set
        expect(child.phase).to eq(:preload)
      end

      it 'can override parent phase in subclass' do
        parent = new_test_class do
          @phase = :preload
        end
        child = Class.new(parent) do
          @phase = :fork_sensitive
        end
        expect(child.phase).to eq(:fork_sensitive)
      end
    end

    context 'phase value validation' do
      it 'accepts :preload as valid phase' do
        klass = new_test_class do
          @phase = :preload
        end
        expect(klass.phase).to eq(:preload)
      end

      it 'accepts :fork_sensitive as valid phase' do
        klass = new_test_class do
          @phase = :fork_sensitive
        end
        expect(klass.phase).to eq(:fork_sensitive)
      end

      # Note: The base class doesn't validate phase values at the class level.
      # Validation happens in InitializerRegistry during load_all.
      it 'stores arbitrary phase values without validation' do
        klass = new_test_class do
          @phase = :invalid_phase
        end
        expect(klass.phase).to eq(:invalid_phase)
      end
    end
  end

  describe 'instance method delegation' do
    describe '#cleanup' do
      it 'does not exist on base class (must be defined by subclass)' do
        instance = described_class.allocate
        expect(instance).not_to respond_to(:cleanup)
      end

      it 'can be implemented in subclass' do
        klass = new_test_class do
          def cleanup
            @cleanup_called = true
          end
        end
        instance = klass.new
        expect(instance).to respond_to(:cleanup)
      end

      it 'can be overridden with custom logic' do
        klass = new_test_class do
          @phase = :fork_sensitive
          def cleanup
            'custom cleanup'
          end
        end
        instance = klass.new
        expect(instance.cleanup).to eq('custom cleanup')
      end

      it 'allows subclass to track cleanup state' do
        klass = new_test_class do
          @phase = :fork_sensitive
          attr_reader :cleanup_called

          def cleanup
            @cleanup_called = true
          end
        end
        instance = klass.new
        expect(instance.cleanup_called).to be_nil
        instance.cleanup
        expect(instance.cleanup_called).to be true
      end

      it 'handles errors in cleanup implementation' do
        klass = new_test_class do
          @phase = :fork_sensitive
          def cleanup
            raise StandardError, 'cleanup failed'
          end
        end
        instance = klass.new
        expect { instance.cleanup }.to raise_error(StandardError, 'cleanup failed')
      end
    end

    describe '#reconnect' do
      it 'does not exist on base class (must be defined by subclass)' do
        instance = described_class.allocate
        expect(instance).not_to respond_to(:reconnect)
      end

      it 'can be implemented in subclass' do
        klass = new_test_class do
          def reconnect
            @reconnect_called = true
          end
        end
        instance = klass.new
        expect(instance).to respond_to(:reconnect)
      end

      it 'can be overridden with custom logic' do
        klass = new_test_class do
          @phase = :fork_sensitive
          def reconnect
            'custom reconnect'
          end
        end
        instance = klass.new
        expect(instance.reconnect).to eq('custom reconnect')
      end

      it 'allows subclass to track reconnect state' do
        klass = new_test_class do
          @phase = :fork_sensitive
          attr_reader :reconnect_called

          def reconnect
            @reconnect_called = true
          end
        end
        instance = klass.new
        expect(instance.reconnect_called).to be_nil
        instance.reconnect
        expect(instance.reconnect_called).to be true
      end

      it 'handles errors in reconnect implementation' do
        klass = new_test_class do
          @phase = :fork_sensitive
          def reconnect
            raise StandardError, 'reconnect failed'
          end
        end
        instance = klass.new
        expect { instance.reconnect }.to raise_error(StandardError, 'reconnect failed')
      end
    end

    describe 'default implementations' do
      it 'base Initializer class does not define cleanup or reconnect' do
        # Note: The base class doesn't enforce this - validation happens
        # in InitializerRegistry.validate_fork_sensitive_initializers!
        # Check base class directly without creating a subclass (which would register)
        expect(described_class.instance_methods(false)).not_to include(:cleanup)
        expect(described_class.instance_methods(false)).not_to include(:reconnect)
      end

      it 'preload initializers default to preload phase' do
        klass = new_test_class # default phase is :preload
        instance = klass.new
        expect(instance.phase).to eq(:preload)
        # Note: test helper adds cleanup/reconnect to avoid polluting other tests,
        # but base Initializer class does not require them for preload phase
      end
    end
  end

  describe 'auto-registration' do
    before do
      # Reset instances but preserve registered classes
      Onetime::Boot::InitializerRegistry.reset!
    end

    after do
      # Reset instances but preserve production initializer classes
      Onetime::Boot::InitializerRegistry.reset!
    end

    context 'class registration' do
      it 'registers with InitializerRegistry on class definition' do
        klass = new_test_class
        registered_classes = Onetime::Boot::InitializerRegistry.instance_variable_get(:@registered_classes)
        expect(registered_classes).to include(klass)
      end

      it 'includes phase information when registered' do
        klass = new_test_class do
          @phase = :fork_sensitive
          def cleanup; end
          def reconnect; end
        end

        Onetime::Boot::InitializerRegistry.load_all
        initializers = Onetime::Boot::InitializerRegistry.initializers
        initializer = initializers.find { |i| i.class == klass }

        expect(initializer).not_to be_nil
        expect(initializer.phase).to eq(:fork_sensitive)
      end

      it 'registers subclasses separately from parent' do
        parent = new_test_class('ParentInitializer')
        child = Class.new(parent) do
          define_singleton_method(:name) { 'ChildInitializer' }
        end

        registered_classes = Onetime::Boot::InitializerRegistry.instance_variable_get(:@registered_classes)
        expect(registered_classes).to include(parent)
        expect(registered_classes).to include(child)
        expect(parent).not_to eq(child)
      end

      it 'registration happens at class definition time' do
        # Verify registry is initially empty
        registered_classes = Onetime::Boot::InitializerRegistry.instance_variable_get(:@registered_classes)
        initial_count = registered_classes.size

        # Define new class
        klass = new_test_class

        # Verify it was immediately registered
        registered_classes = Onetime::Boot::InitializerRegistry.instance_variable_get(:@registered_classes)
        expect(registered_classes.size).to eq(initial_count + 1)
        expect(registered_classes.last).to eq(klass)
      end

      it 'prevents duplicate registration of same class' do
        klass = new_test_class
        registered_classes = Onetime::Boot::InitializerRegistry.instance_variable_get(:@registered_classes)
        initial_count = registered_classes.count(klass)

        # Try to register again manually (simulating duplicate inherited call)
        Onetime::Boot::InitializerRegistry.register_class(klass)

        registered_classes = Onetime::Boot::InitializerRegistry.instance_variable_get(:@registered_classes)
        expect(registered_classes.count(klass)).to eq(initial_count)
      end
    end

    context 'retrieving registered initializers' do
      it 'can retrieve registered initializers after load_all' do
        klass1 = new_test_class('TestInit1')
        klass2 = new_test_class('TestInit2')

        Onetime::Boot::InitializerRegistry.load_all
        initializers = Onetime::Boot::InitializerRegistry.initializers

        classes = initializers.map(&:class)
        expect(classes).to include(klass1)
        expect(classes).to include(klass2)
      end

      it 'creates instances during load_all' do
        klass = new_test_class('TestInit')

        Onetime::Boot::InitializerRegistry.load_all
        initializers = Onetime::Boot::InitializerRegistry.initializers

        initializer = initializers.find { |i| i.class == klass }
        expect(initializer).to be_a(klass)
        expect(initializer).to be_a(Onetime::Boot::Initializer)
      end

      it 'preserves phase information in instances' do
        preload_class = new_test_class('PreloadInit') # default :preload
        fork_class = new_test_class('ForkInit') do
          @phase = :fork_sensitive
          def cleanup; end
          def reconnect; end
        end

        Onetime::Boot::InitializerRegistry.load_all
        initializers = Onetime::Boot::InitializerRegistry.initializers

        preload_init = initializers.find { |i| i.class == preload_class }
        fork_init = initializers.find { |i| i.class == fork_class }

        expect(preload_init.phase).to eq(:preload)
        expect(fork_init.phase).to eq(:fork_sensitive)
      end
    end
  end

  # Integration test: Verify phase infrastructure works with registry
  describe 'phase infrastructure integration' do
    before do
      # Use reset! to clear instances but preserve registered classes
      Onetime::Boot::InitializerRegistry.reset!
    end

    after do
      # Use reset! to avoid clearing production initializer classes
      Onetime::Boot::InitializerRegistry.reset!
    end

    it 'fork_sensitive initializers appear in fork_sensitive_initializers list' do
      preload = new_test_class do
        @phase = :preload
      end
      fork_sensitive = new_test_class do
        @phase = :fork_sensitive
        def cleanup; end
        def reconnect; end
      end

      Onetime::Boot::InitializerRegistry.load_all
      fork_list = Onetime::Boot::InitializerRegistry.fork_sensitive_initializers

      expect(fork_list.map(&:class)).to include(fork_sensitive)
      expect(fork_list.map(&:class)).not_to include(preload)
    end

    it 'validates fork_sensitive initializers have required methods during load' do
      # Create class directly (not via helper) to test validation behavior
      invalid_class = Class.new(described_class) do
        define_singleton_method(:name) { "InvalidForkSensitiveTestClass#{object_id}" }
        @phase = :fork_sensitive
        def execute(_context); end
        # Missing cleanup and reconnect methods intentionally
      end

      expect {
        Onetime::Boot::InitializerRegistry.load_all
      }.to raise_error(Onetime::Problem, /must implement.*cleanup.*reconnect/)

      # Clean up: remove just this invalid class to avoid polluting other tests
      Onetime::Boot::InitializerRegistry.unregister_class(invalid_class)
    end

    it 'allows preload initializers without cleanup/reconnect methods' do
      new_test_class do
        @phase = :preload
        # No cleanup/reconnect needed
      end

      expect {
        Onetime::Boot::InitializerRegistry.load_all
      }.not_to raise_error
    end
  end
end
