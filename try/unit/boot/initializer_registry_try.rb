# try/unit/boot/initializer_registry_try.rb
#
# frozen_string_literal: true

# Unit test - just load the registry, not the full app
require_relative '../../../lib/onetime/boot/initializer_registry'

## Setup
# Mock Onetime methods for testing
::Onetime.define_singleton_method(:now_in_μs) do
  (Time.now.to_f * 1_000_000).to_i
end

::Onetime.define_singleton_method(:debug?) do
  false
end

# Mock logger to avoid dependencies
require 'logger'
::Onetime.define_singleton_method(:app_logger) do
  @test_logger ||= Logger.new('/dev/null')
end

# Reset before tests
Onetime::Boot::InitializerRegistry.reset!

## Classes auto-register via inherited hook
Onetime::Boot::InitializerRegistry.reset!
# Define new class (triggers inherited hook)
class TestAutoRegister < Onetime::Boot::Initializer
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.initializers.size
#=> 1

## Dependency resolution orders correctly
Onetime::Boot::InitializerRegistry.reset!
class TestA < Onetime::Boot::Initializer
  @provides = [:a]
  def execute(_ctx); end
end
class TestB < Onetime::Boot::Initializer
  @depends_on = [:a]
  @provides = [:b]
  def execute(_ctx); end
end
class TestC < Onetime::Boot::Initializer
  @depends_on = [:a, :b]
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.execution_order.map(&:name)
#=> [:test_a, :test_b, :test_c]

## Initializers execute in order
Onetime::Boot::InitializerRegistry.reset!
order = []
class TestFirst < Onetime::Boot::Initializer
  @provides = [:first]
  define_method(:execute) { |_ctx| order << :first }
end
class TestSecond < Onetime::Boot::Initializer
  @depends_on = [:first]
  define_method(:execute) { |_ctx| order << :second }
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.run_all
order
#=> [:first, :second]

## Context is shared
Onetime::Boot::InitializerRegistry.reset!
class TestContextA < Onetime::Boot::Initializer
  def execute(ctx); ctx[:a] = 1; end
end
class TestContextB < Onetime::Boot::Initializer
  def execute(ctx); ctx[:b] = 2; end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.run_all
ctx = Onetime::Boot::InitializerRegistry.context
[ctx[:a], ctx[:b]]
#=> [1, 2]

## Optional failures don't stop boot
Onetime::Boot::InitializerRegistry.reset!
class TestRequired < Onetime::Boot::Initializer
  @provides = [:required]
  def execute(_ctx); end
end
class TestOptionalFail < Onetime::Boot::Initializer
  @depends_on = [:required]
  @optional = true
  def execute(_ctx); raise 'fail'; end
end
class TestAfter < Onetime::Boot::Initializer
  @depends_on = [:required]
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
res = Onetime::Boot::InitializerRegistry.run_all
res[:successful].size
#=> 2

## Failed initializers are tracked
Onetime::Boot::InitializerRegistry.reset!
class TestFailTracked < Onetime::Boot::Initializer
  @optional = true
  def execute(_ctx); raise 'error'; end
end
Onetime::Boot::InitializerRegistry.load_all
res = Onetime::Boot::InitializerRegistry.run_all
res[:failed].size
#=> 1

## Skipped when dependency fails
Onetime::Boot::InitializerRegistry.reset!
class TestBase < Onetime::Boot::Initializer
  @provides = [:base]
  @optional = true
  def execute(_ctx); raise 'fail'; end
end
class TestDependent < Onetime::Boot::Initializer
  @depends_on = [:base]
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
res = Onetime::Boot::InitializerRegistry.run_all
res[:skipped].size
#=> 1

## Circular dependencies detected
Onetime::Boot::InitializerRegistry.reset!
class TestCircA < Onetime::Boot::Initializer
  @depends_on = [:b]
  @provides = [:a]
  def execute(_ctx); end
end
class TestCircB < Onetime::Boot::Initializer
  @depends_on = [:a]
  @provides = [:b]
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
begin
  Onetime::Boot::InitializerRegistry.execution_order
  'should have raised'
rescue TSort::Cyclic
  'circular dependency detected'
end
#=> "circular dependency detected"

## Duplicate capability providers rejected
Onetime::Boot::InitializerRegistry.reset!
class TestProviderA < Onetime::Boot::Initializer
  @provides = [:capability]
  def execute(_ctx); end
end
class TestProviderB < Onetime::Boot::Initializer
  @provides = [:capability]
  def execute(_ctx); end
end
begin
  Onetime::Boot::InitializerRegistry.load_all
  'should have raised'
rescue ArgumentError => e
  e.message.include?('already provided')
end
#=> true

## Health check reports status
Onetime::Boot::InitializerRegistry.reset!
class TestHealthy < Onetime::Boot::Initializer
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.run_all
health = Onetime::Boot::InitializerRegistry.health_check
health[:healthy]
#=> true

## Teardown
Onetime::Boot::InitializerRegistry.reset!
