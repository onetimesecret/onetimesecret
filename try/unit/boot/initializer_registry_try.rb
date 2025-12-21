# try/unit/boot/initializer_registry_try.rb
#
# frozen_string_literal: true

# Unit test - just load the registry, not the full app
require_relative '../../../lib/onetime/logger_methods'
require_relative '../../../lib/onetime/errors'
require_relative '../../../lib/onetime/boot/initializer_registry'

# Setup section
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

## Default phase is :preload
Onetime::Boot::InitializerRegistry.reset_all!
class TestDefaultPhase < Onetime::Boot::Initializer
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
init = Onetime::Boot::InitializerRegistry.initializers.first
init.phase
#=> :preload

## Phase :fork_sensitive is recognized
Onetime::Boot::InitializerRegistry.reset_all!
class TestForkSensitive < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; end
end
Onetime::Boot::InitializerRegistry.load_all
init = Onetime::Boot::InitializerRegistry.initializers.first
init.phase
#=> :fork_sensitive

## fork_sensitive_initializers filters correctly
Onetime::Boot::InitializerRegistry.reset_all!
class TestPreload1 < Onetime::Boot::Initializer
  def execute(_ctx); end
end
class TestFork1 < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; end
end
class TestPreload2 < Onetime::Boot::Initializer
  def execute(_ctx); end
end
Onetime::Boot::InitializerRegistry.load_all
fork_sensitive = Onetime::Boot::InitializerRegistry.fork_sensitive_initializers
fork_sensitive.size
#=> 1

## Validation catches missing cleanup method
Onetime::Boot::InitializerRegistry.reset_all!
class TestMissingCleanup < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def reconnect; end
end
begin
  Onetime::Boot::InitializerRegistry.load_all
  'should have raised'
rescue Onetime::Problem => ex
  ex.message.include?('cleanup')
end
#=> true

## Validation catches missing reconnect method
Onetime::Boot::InitializerRegistry.reset_all!
class TestMissingReconnect < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
end
begin
  Onetime::Boot::InitializerRegistry.load_all
  'should have raised'
rescue Onetime::Problem => ex
  ex.message.include?('reconnect')
end
#=> true

## Validation catches both missing methods
Onetime::Boot::InitializerRegistry.reset_all!
class TestMissingBoth < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
end
begin
  Onetime::Boot::InitializerRegistry.load_all
  'should have raised'
rescue Onetime::Problem => ex
  ex.message.include?('cleanup') && ex.message.include?('reconnect')
end
#=> true

## cleanup_before_fork calls cleanup methods
Onetime::Boot::InitializerRegistry.reset_all!
$cleanup_called = []
class TestCleanup1 < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; $cleanup_called << :cleanup1; end
  def reconnect; end
end
class TestCleanup2 < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; $cleanup_called << :cleanup2; end
  def reconnect; end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.cleanup_before_fork
$cleanup_called.sort
#=> [:cleanup1, :cleanup2]

## reconnect_after_fork calls reconnect methods
Onetime::Boot::InitializerRegistry.reset_all!
$reconnect_called = []
class TestReconnect1 < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; $reconnect_called << :reconnect1; end
end
class TestReconnect2 < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; $reconnect_called << :reconnect2; end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.reconnect_after_fork
$reconnect_called.sort
#=> [:reconnect1, :reconnect2]

## cleanup_before_fork handles errors gracefully
Onetime::Boot::InitializerRegistry.reset_all!
$cleanup_ok = false
class TestCleanupError < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; raise 'cleanup error'; end
  def reconnect; end
end
class TestCleanupOk < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; $cleanup_ok = true; end
  def reconnect; end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.cleanup_before_fork
$cleanup_ok
#=> true

## reconnect_after_fork handles errors gracefully
Onetime::Boot::InitializerRegistry.reset_all!
$reconnect_ok = false
class TestReconnectError < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; raise 'reconnect error'; end
end
class TestReconnectOk < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; $reconnect_ok = true; end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.reconnect_after_fork
$reconnect_ok
#=> true

## cleanup_before_fork catches StandardError subclasses
Onetime::Boot::InitializerRegistry.reset_all!
$cleanup_after_error = false
class TestStandardErrorCleanup < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; raise IOError, 'connection failed'; end
  def reconnect; end
end
class TestCleanupAfterStandardError < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; $cleanup_after_error = true; end
  def reconnect; end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.cleanup_before_fork
$cleanup_after_error
#=> true

## reconnect_after_fork catches StandardError subclasses
Onetime::Boot::InitializerRegistry.reset_all!
$reconnect_after_error = false
class TestStandardErrorReconnect < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; raise Timeout::Error, 'timeout'; end
end
class TestReconnectAfterStandardError < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; $reconnect_after_error = true; end
end
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.reconnect_after_fork
$reconnect_after_error
#=> true

## cleanup_before_fork does NOT catch non-StandardError exceptions
Onetime::Boot::InitializerRegistry.reset_all!
class TestNonStandardErrorCleanup < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; raise SignalException, 'SIGTERM'; end
  def reconnect; end
end
Onetime::Boot::InitializerRegistry.load_all
begin
  Onetime::Boot::InitializerRegistry.cleanup_before_fork
  'should have raised'
rescue SignalException
  'propagated correctly'
end
#=> "propagated correctly"

## reconnect_after_fork does NOT catch non-StandardError exceptions
Onetime::Boot::InitializerRegistry.reset_all!
class TestNonStandardErrorReconnect < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; raise SystemExit, 'exit'; end
end
Onetime::Boot::InitializerRegistry.load_all
begin
  Onetime::Boot::InitializerRegistry.reconnect_after_fork
  'should have raised'
rescue SystemExit
  'propagated correctly'
end
#=> "propagated correctly"

## NoMethodError re-raised (cleanup missing) - exposes validation bugs
Onetime::Boot::InitializerRegistry.reset_all!
class TestNoCleanup < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def reconnect; end
end
# Manually bypass validation for this test
Onetime::Boot::InitializerRegistry.instance_variable_set(:@initializers, [])
init = TestNoCleanup.new
Onetime::Boot::InitializerRegistry.instance_variable_get(:@initializers) << init
begin
  Onetime::Boot::InitializerRegistry.cleanup_before_fork
  'should have raised'
rescue NoMethodError
  'raised as expected'
end
#=> "raised as expected"

## NoMethodError re-raised (reconnect missing) - exposes validation bugs
Onetime::Boot::InitializerRegistry.reset_all!
class TestNoReconnect < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
end
# Manually bypass validation for this test
Onetime::Boot::InitializerRegistry.instance_variable_set(:@initializers, [])
init = TestNoReconnect.new
Onetime::Boot::InitializerRegistry.instance_variable_get(:@initializers) << init
begin
  Onetime::Boot::InitializerRegistry.reconnect_after_fork
  'should have raised'
rescue NoMethodError
  'raised as expected'
end
#=> "raised as expected"

## Full reset to prevent test class pollution
Onetime::Boot::InitializerRegistry.reset_all!
