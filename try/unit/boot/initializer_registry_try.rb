# try/unit/boot/initializer_registry_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/boot/initializer'
require_relative '../../../lib/onetime/boot/initializer_registry'

## Setup
# Reset before tests
Onetime::Boot::InitializerRegistry.reset!

## Basic registration works
Onetime::Boot::InitializerRegistry.reset!
result = Onetime::Boot::InitializerRegistry.register(
  name: :test_init,
  description: 'Test initializer'
) { |ctx| ctx[:test] = 'value' }
result.class
#=> Onetime::Boot::Initializer

## Registered initializer is stored
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :test) { |_| }
Onetime::Boot::InitializerRegistry.initializers.size
#=> 1

## Dependency resolution orders correctly
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :config, provides: [:config]) { |_| }
Onetime::Boot::InitializerRegistry.register(name: :logging, depends_on: [:config], provides: [:logging]) { |_| }
Onetime::Boot::InitializerRegistry.register(name: :database, depends_on: [:config, :logging]) { |_| }
Onetime::Boot::InitializerRegistry.execution_order.map(&:name)
#=> [:config, :logging, :database]

## Initializers execute in order
Onetime::Boot::InitializerRegistry.reset!
order = []
Onetime::Boot::InitializerRegistry.register(name: :first, provides: [:first]) { order << :first }
Onetime::Boot::InitializerRegistry.register(name: :second, depends_on: [:first]) { order << :second }
Onetime::Boot::InitializerRegistry.run_all
order
#=> [:first, :second]

## Context is shared
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :a) { |ctx| ctx[:a] = 1 }
Onetime::Boot::InitializerRegistry.register(name: :b) { |ctx| ctx[:b] = 2 }
Onetime::Boot::InitializerRegistry.run_all
ctx = Onetime::Boot::InitializerRegistry.context
[ctx[:a], ctx[:b]]
#=> [1, 2]

## Optional failures don't stop boot
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :required, provides: [:required]) { |_| }
Onetime::Boot::InitializerRegistry.register(name: :optional, depends_on: [:required], optional: true) { raise 'fail' }
Onetime::Boot::InitializerRegistry.register(name: :after, depends_on: [:required]) { |_| }
res = Onetime::Boot::InitializerRegistry.run_all
res[:successful].size
#=> 2

## Failed initializers are tracked
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :fail, optional: true) { raise 'error' }
res = Onetime::Boot::InitializerRegistry.run_all
res[:failed].size
#=> 1

## Skipped when dependency fails
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :base, provides: [:base], optional: true) { raise 'fail' }
Onetime::Boot::InitializerRegistry.register(name: :dependent, depends_on: [:base]) { |_| }
res = Onetime::Boot::InitializerRegistry.run_all
res[:skipped].size
#=> 1

## Circular dependencies detected
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :a, depends_on: [:b], provides: [:a]) { |_| }
Onetime::Boot::InitializerRegistry.register(name: :b, depends_on: [:a], provides: [:b]) { |_| }
begin
  Onetime::Boot::InitializerRegistry.execution_order
  'failed'
rescue TSort::Cyclic
  'detected'
end
#=> 'detected'

## Duplicate names rejected
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :dup) { |_| }
begin
  Onetime::Boot::InitializerRegistry.register(name: :dup) { |_| }
  false
rescue ArgumentError
  true
end
#=> true

## Duplicate capabilities rejected
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :first, provides: [:shared]) { |_| }
begin
  Onetime::Boot::InitializerRegistry.register(name: :second, provides: [:shared]) { |_| }
  false
rescue ArgumentError
  true
end
#=> true

## Unknown dependencies detected
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :test, depends_on: [:missing]) { |_| }
begin
  Onetime::Boot::InitializerRegistry.execution_order
  false
rescue ArgumentError
  true
end
#=> true

## Health check works
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :init1) { |_| }
Onetime::Boot::InitializerRegistry.register(name: :init2) { |_| }
Onetime::Boot::InitializerRegistry.run_all
health = Onetime::Boot::InitializerRegistry.health_check
health[:healthy]
#=> true

## Health check counts
Onetime::Boot::InitializerRegistry.reset!
Onetime::Boot::InitializerRegistry.register(name: :a) { |_| }
Onetime::Boot::InitializerRegistry.register(name: :b) { |_| }
Onetime::Boot::InitializerRegistry.run_all
Onetime::Boot::InitializerRegistry.health_check[:total]
#=> 2

## Teardown
Onetime::Boot::InitializerRegistry.reset!
