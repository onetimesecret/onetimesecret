# try/integration/boot/app_initializers_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/boot/initializer_registry'

## Reset registry before all tests
Onetime::Boot::InitializerRegistry.reset!

## App can register initializer with DSL
class AppWithInit < Onetime::Application::Base
  initializer :app_init do |_ctx|
    # Test code
  end
end

Onetime::Boot::InitializerRegistry.load_all
found = Onetime::Boot::InitializerRegistry.initializers.any? { |i| i.name == :app_init }
found
#=> true

## Initializer can have dependencies
class AppWithDeps < Onetime::Application::Base
  initializer :base_init, provides: [:base] do |_ctx|
  end

  initializer :dependent_init, depends_on: [:base] do |_ctx|
  end
end

Onetime::Boot::InitializerRegistry.load_all
base = Onetime::Boot::InitializerRegistry.initializers.find { |i| i.name == :base_init }
base.provides
#=> [:base]

## Dependent initializer has correct dependencies
dependent = Onetime::Boot::InitializerRegistry.initializers.find { |i| i.name == :dependent_init }
dependent.dependencies
#=> [:base]

## Dependency ordering resolves correctly
order = Onetime::Boot::InitializerRegistry.execution_order
base_idx = order.find_index { |i| i.name == :base_init }
dep_idx = order.find_index { |i| i.name == :dependent_init }
base_idx < dep_idx
#=> true

## App can register optional initializer
class AppWithOptional < Onetime::Application::Base
  initializer :optional_init, optional: true do |_ctx|
    # Test code
  end
end

Onetime::Boot::InitializerRegistry.load_all
optional = Onetime::Boot::InitializerRegistry.initializers.find { |i| i.name == :optional_init }
optional.optional
#=> true

## Initializer provides capability
class AppWithCapability < Onetime::Application::Base
  initializer :provider, provides: [:test_capability] do |_ctx|
  end
end

Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.capability_map.key?(:test_capability)
#=> true

## Capability maps to correct initializer
Onetime::Boot::InitializerRegistry.capability_map[:test_capability].name
#=> :provider

## Initializer tracks application class
class AppForTracking < Onetime::Application::Base
  initializer :tracked_init do |_ctx|
  end
end

Onetime::Boot::InitializerRegistry.load_all
tracked = Onetime::Boot::InitializerRegistry.initializers.find { |i| i.name == :tracked_init }
tracked.application_class
#=> AppForTracking

## Initializer can have description
class AppWithDescription < Onetime::Application::Base
  initializer :described_init, description: 'Custom description' do |_ctx|
  end
end

Onetime::Boot::InitializerRegistry.load_all
described = Onetime::Boot::InitializerRegistry.initializers.find { |i| i.name == :described_init }
described.description
#=> 'Custom description'

# Teardown section
Onetime::Boot::InitializerRegistry.reset!
