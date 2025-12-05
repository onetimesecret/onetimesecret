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

# Full reset to clear any classes from previous test files
# This ensures test isolation when running in batch mode
Onetime::Boot::InitializerRegistry.reset_all!

## Classes auto-register via inherited hook
# Define new class (triggers inherited hook)
class TestAutoRegister < Onetime::Boot::Initializer
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.initializers.size
#=> 1

## Dependency resolution orders correctly - test name patterns
Onetime::Boot::InitializerRegistry.reset_all!
class TestDepA < Onetime::Boot::Initializer
  @provides = [:a]
  def execute(_ctx); end
end
class TestDepB < Onetime::Boot::Initializer
  @depends_on = [:a]
  @provides = [:b]
  def execute(_ctx); end
end
class TestDepC < Onetime::Boot::Initializer
  @depends_on = [:a, :b]
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
names = Onetime::Boot::InitializerRegistry.execution_order.map(&:name)
# Names include anonymous class prefix, but ordering should be correct
[names[0].to_s.include?('test_dep_a'), names[1].to_s.include?('test_dep_b'), names[2].to_s.include?('test_dep_c')]
#=> [true, true, true]

## Context is shared between initializers
Onetime::Boot::InitializerRegistry.reset_all!
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
Onetime::Boot::InitializerRegistry.reset_all!
class TestOptRequired < Onetime::Boot::Initializer
  @provides = [:required]
  def execute(_ctx); end
end
class TestOptionalFail < Onetime::Boot::Initializer
  @depends_on = [:required]
  @optional = true
  def execute(_ctx); raise 'fail'; end
end
class TestOptAfter < Onetime::Boot::Initializer
  @depends_on = [:required]
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
res = Onetime::Boot::InitializerRegistry.run_all
res[:successful].size
#=> 2

## Failed initializers are tracked
Onetime::Boot::InitializerRegistry.reset_all!
class TestFailTracked < Onetime::Boot::Initializer
  @optional = true
  def execute(_ctx); raise 'error'; end
end
Onetime::Boot::InitializerRegistry.load_all
res = Onetime::Boot::InitializerRegistry.run_all
res[:failed].size
#=> 1

## Skipped when dependency fails
Onetime::Boot::InitializerRegistry.reset_all!
class TestSkipBase < Onetime::Boot::Initializer
  @provides = [:base]
  @optional = true
  def execute(_ctx); raise 'fail'; end
end
class TestSkipDependent < Onetime::Boot::Initializer
  @depends_on = [:base]
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
res = Onetime::Boot::InitializerRegistry.run_all
res[:skipped].size
#=> 1

## Circular dependencies detected
Onetime::Boot::InitializerRegistry.reset_all!
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

## Health check reports status
Onetime::Boot::InitializerRegistry.reset_all!
class TestHealthy < Onetime::Boot::Initializer
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.run_all
health = Onetime::Boot::InitializerRegistry.health_check
health[:healthy]
#=> true

## Teardown - Full reset to prevent test class pollution
Onetime::Boot::InitializerRegistry.reset_all!
