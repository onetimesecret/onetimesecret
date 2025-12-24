# try/integration/boot/app_initializers_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/boot/initializer_registry'

# Setup section
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry

## App can register initializer with DSL
class AppWithInit < Onetime::Application::Base
  initializer :app_init do |_ctx|
    # Test code
  end
end

@registry.load_all
found = @registry.initializers.any? { |i| i.name == :app_init }
found
#=> true

## Initializer can have dependencies
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class AppWithDeps < Onetime::Application::Base
  initializer :base_init, provides: [:base] do |_ctx|
  end

  initializer :dependent_init, depends_on: [:base] do |_ctx|
  end
end

@registry.load_all
base = @registry.initializers.find { |i| i.name == :base_init }
base.provides
#=> [:base]

## Dependent initializer has correct dependencies
dependent = @registry.initializers.find { |i| i.name == :dependent_init }
dependent.dependencies
#=> [:base]

## Dependency ordering resolves correctly
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class AppForOrdering < Onetime::Application::Base
  initializer :base_init, provides: [:base] do |_ctx|
  end

  initializer :dependent_init, depends_on: [:base] do |_ctx|
  end
end
@registry.load_all
order = @registry.execution_order
base_idx = order.find_index { |i| i.name == :base_init }
dep_idx = order.find_index { |i| i.name == :dependent_init }
base_idx < dep_idx
#=> true

## App can register optional initializer
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class AppWithOptional < Onetime::Application::Base
  initializer :optional_init, optional: true do |_ctx|
    # Test code
  end
end

@registry.load_all
optional = @registry.initializers.find { |i| i.name == :optional_init }
optional.optional
#=> true

## Initializer provides capability
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class AppWithCapability < Onetime::Application::Base
  initializer :provider, provides: [:test_capability] do |_ctx|
  end
end

@registry.load_all
@registry.capability_map.key?(:test_capability)
#=> true

## Capability maps to correct initializer
@registry.capability_map[:test_capability].name
#=> :provider

## Initializer tracks application class
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class AppForTracking < Onetime::Application::Base
  initializer :tracked_init do |_ctx|
  end
end

@registry.load_all
tracked = @registry.initializers.find { |i| i.name == :tracked_init }
tracked.application_class
#=> AppForTracking

## Initializer can have description
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class AppWithDescription < Onetime::Application::Base
  initializer :described_init, description: 'Custom description' do |_ctx|
  end
end

@registry.load_all
described = @registry.initializers.find { |i| i.name == :described_init }
described.description
#=> 'Custom description'

# Teardown section - clear thread-local binding
Onetime::Boot::InitializerRegistry.current = nil
