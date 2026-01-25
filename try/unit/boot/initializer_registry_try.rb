# try/unit/boot/initializer_registry_try.rb
#
# frozen_string_literal: true

# Unit test - just load the registry, not the full app
# Pure DI pattern: explicit registration, no inherited hook dependency
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

## Explicit registration works
@registry = Onetime::Boot::InitializerRegistry.new
class TestExplicitRegister < Onetime::Boot::Initializer
  def execute(_ctx); end
end
@registry.load([TestExplicitRegister])
@registry.initializers.size
#=> 1

## Dependency resolution orders correctly - test name patterns
@registry = Onetime::Boot::InitializerRegistry.new
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
@registry.load([TestDepA, TestDepB, TestDepC])
names = @registry.execution_order.map(&:name)
# Names include anonymous class prefix, but ordering should be correct
[names[0].to_s.include?('test_dep_a'), names[1].to_s.include?('test_dep_b'), names[2].to_s.include?('test_dep_c')]
#=> [true, true, true]

## Context is shared between initializers
@registry = Onetime::Boot::InitializerRegistry.new
class TestContextA < Onetime::Boot::Initializer
  def execute(ctx); ctx[:a] = 1; end
end
class TestContextB < Onetime::Boot::Initializer
  def execute(ctx); ctx[:b] = 2; end
end
@registry.load([TestContextA, TestContextB])
@registry.run_all
ctx = @registry.context
[ctx[:a], ctx[:b]]
#=> [1, 2]

## Optional failures don't stop boot
@registry = Onetime::Boot::InitializerRegistry.new
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
@registry.load([TestOptRequired, TestOptionalFail, TestOptAfter])
res = @registry.run_all
res[:successful].size
#=> 2

## Failed initializers are tracked
@registry = Onetime::Boot::InitializerRegistry.new
class TestFailTracked < Onetime::Boot::Initializer
  @optional = true
  def execute(_ctx); raise 'error'; end
end
@registry.load([TestFailTracked])
res = @registry.run_all
res[:failed].size
#=> 1

## Skipped when dependency fails
@registry = Onetime::Boot::InitializerRegistry.new
class TestSkipBase < Onetime::Boot::Initializer
  @provides = [:base]
  @optional = true
  def execute(_ctx); raise 'fail'; end
end
class TestSkipDependent < Onetime::Boot::Initializer
  @depends_on = [:base]
  def execute(_ctx); end
end
@registry.load([TestSkipBase, TestSkipDependent])
res = @registry.run_all
res[:skipped].size
#=> 1

## Circular dependencies detected
@registry = Onetime::Boot::InitializerRegistry.new
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
@registry.load([TestCircA, TestCircB])
begin
  @registry.execution_order
  'should have raised'
rescue TSort::Cyclic
  'circular dependency detected'
end
#=> "circular dependency detected"

## Health check reports status
@registry = Onetime::Boot::InitializerRegistry.new
class TestHealthy < Onetime::Boot::Initializer
  def execute(_ctx); end
end
@registry.load([TestHealthy])
@registry.run_all
health = @registry.health_check
health[:healthy]
#=> true

## Default phase is :preload
@registry = Onetime::Boot::InitializerRegistry.new
class TestDefaultPhase < Onetime::Boot::Initializer
  def execute(_ctx); end
end
@registry.load([TestDefaultPhase])
init = @registry.initializers.first
init.phase
#=> :preload

## Phase :fork_sensitive is recognized
@registry = Onetime::Boot::InitializerRegistry.new
class TestForkSensitive < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; end
end
@registry.load([TestForkSensitive])
init = @registry.initializers.first
init.phase
#=> :fork_sensitive

## fork_sensitive_initializers filters correctly
@registry = Onetime::Boot::InitializerRegistry.new
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
@registry.load([TestPreload1, TestFork1, TestPreload2])
fork_sensitive = @registry.fork_sensitive_initializers
fork_sensitive.size
#=> 1

## Validation catches missing cleanup method
@registry = Onetime::Boot::InitializerRegistry.new
class TestMissingCleanup < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def reconnect; end
end
begin
  @registry.load([TestMissingCleanup])
  'should have raised'
rescue Onetime::Problem => ex
  ex.message.include?('cleanup')
end
#=> true

## Validation catches missing reconnect method
@registry = Onetime::Boot::InitializerRegistry.new
class TestMissingReconnect < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
end
begin
  @registry.load([TestMissingReconnect])
  'should have raised'
rescue Onetime::Problem => ex
  ex.message.include?('reconnect')
end
#=> true

## Validation catches both missing methods
@registry = Onetime::Boot::InitializerRegistry.new
class TestMissingBoth < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
end
begin
  @registry.load([TestMissingBoth])
  'should have raised'
rescue Onetime::Problem => ex
  ex.message.include?('cleanup') && ex.message.include?('reconnect')
end
#=> true

## cleanup_before_fork calls cleanup methods
@registry = Onetime::Boot::InitializerRegistry.new
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
@registry.load([TestCleanup1, TestCleanup2])
@registry.cleanup_before_fork
$cleanup_called.sort
#=> [:cleanup1, :cleanup2]

## reconnect_after_fork calls reconnect methods
@registry = Onetime::Boot::InitializerRegistry.new
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
@registry.load([TestReconnect1, TestReconnect2])
@registry.reconnect_after_fork
$reconnect_called.sort
#=> [:reconnect1, :reconnect2]

## cleanup_before_fork handles errors gracefully
@registry = Onetime::Boot::InitializerRegistry.new
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
@registry.load([TestCleanupError, TestCleanupOk])
@registry.cleanup_before_fork
$cleanup_ok
#=> true

## reconnect_after_fork handles errors gracefully
@registry = Onetime::Boot::InitializerRegistry.new
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
@registry.load([TestReconnectError, TestReconnectOk])
@registry.reconnect_after_fork
$reconnect_ok
#=> true

## cleanup_before_fork catches StandardError subclasses
@registry = Onetime::Boot::InitializerRegistry.new
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
@registry.load([TestStandardErrorCleanup, TestCleanupAfterStandardError])
@registry.cleanup_before_fork
$cleanup_after_error
#=> true

## reconnect_after_fork catches StandardError subclasses
@registry = Onetime::Boot::InitializerRegistry.new
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
@registry.load([TestStandardErrorReconnect, TestReconnectAfterStandardError])
@registry.reconnect_after_fork
$reconnect_after_error
#=> true

## cleanup_before_fork does NOT catch non-StandardError exceptions
@registry = Onetime::Boot::InitializerRegistry.new
class TestNonStandardErrorCleanup < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; raise SignalException, 'SIGTERM'; end
  def reconnect; end
end
@registry.load([TestNonStandardErrorCleanup])
begin
  @registry.cleanup_before_fork
  'should have raised'
rescue SignalException
  'propagated correctly'
end
#=> "propagated correctly"

## reconnect_after_fork does NOT catch non-StandardError exceptions
@registry = Onetime::Boot::InitializerRegistry.new
class TestNonStandardErrorReconnect < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
  def reconnect; raise SystemExit, 'exit'; end
end
@registry.load([TestNonStandardErrorReconnect])
begin
  @registry.reconnect_after_fork
  'should have raised'
rescue SystemExit
  'propagated correctly'
end
#=> "propagated correctly"

## NoMethodError re-raised (cleanup missing) - exposes validation bugs
@registry = Onetime::Boot::InitializerRegistry.new
class TestNoCleanup < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def reconnect; end
end
# Manually bypass validation for this test
init = TestNoCleanup.new
@registry.instance_variable_set(:@initializers, [init])
begin
  @registry.cleanup_before_fork
  'should have raised'
rescue NoMethodError
  'raised as expected'
end
#=> "raised as expected"

## NoMethodError re-raised (reconnect missing) - exposes validation bugs
@registry = Onetime::Boot::InitializerRegistry.new
class TestNoReconnect < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  def execute(_ctx); end
  def cleanup; end
end
# Manually bypass validation for this test
init = TestNoReconnect.new
@registry.instance_variable_set(:@initializers, [init])
begin
  @registry.reconnect_after_fork
  'should have raised'
rescue NoMethodError
  'raised as expected'
end
#=> "raised as expected"

# ============================================================
# Anonymous class handling tests
# ============================================================

## Anonymous class without explicit name returns nil for initializer_name
@anon_class = Class.new(Onetime::Boot::Initializer) do
  def execute(_ctx); end
end
@anon_class.initializer_name
#=> nil

## Anonymous class with explicit name returns that name
@anon_with_name = Class.new(Onetime::Boot::Initializer) do
  @initializer_name = :my_custom_initializer
  def execute(_ctx); end
end
@anon_with_name.initializer_name
#=> :my_custom_initializer

## Named class returns derived initializer_name
class TestNamedInit < Onetime::Boot::Initializer
  def execute(_ctx); end
end
TestNamedInit.initializer_name.to_s.include?('test_named_init')
#=> true

## load skips anonymous class without explicit name
@registry = Onetime::Boot::InitializerRegistry.new
@anon_no_name = Class.new(Onetime::Boot::Initializer) do
  def execute(_ctx); end
end
@registry.load([@anon_no_name])
@registry.initializers.size
#=> 0

## load accepts anonymous class with explicit name
@registry = Onetime::Boot::InitializerRegistry.new
@anon_named = Class.new(Onetime::Boot::Initializer) do
  @initializer_name = :explicit_anon_init
  def execute(_ctx); end
end
@registry.load([@anon_named])
@registry.initializers.size
#=> 1

## load mixed: skips anonymous, loads named
@registry = Onetime::Boot::InitializerRegistry.new
@anon_skip = Class.new(Onetime::Boot::Initializer) do
  def execute(_ctx); end
end
class TestMixedNamed < Onetime::Boot::Initializer
  def execute(_ctx); end
end
@anon_keep = Class.new(Onetime::Boot::Initializer) do
  @initializer_name = :anon_with_name
  def execute(_ctx); end
end
@registry.load([@anon_skip, TestMixedNamed, @anon_keep])
@registry.initializers.size
#=> 2

## discover finds classes matching filter
class TestDiscoverMe < Onetime::Boot::Initializer
  def execute(_ctx); end
end
classes = Onetime::Boot::InitializerRegistry.discover { |k| k.name&.include?('TestDiscoverMe') }
classes.size
#=> 1

## discover with anonymous class in ObjectSpace - filtered by load_classes
@registry = Onetime::Boot::InitializerRegistry.new
# Create anonymous class (will be in ObjectSpace)
@floating_anon = Class.new(Onetime::Boot::Initializer) do
  def execute(_ctx); end
end
# discover finds it (no name filter in discover)
found = Onetime::Boot::InitializerRegistry.discover { |k| k == @floating_anon }
found.size
#=> 1

## load_classes filters out anonymous from discover results
@registry = Onetime::Boot::InitializerRegistry.new
@floating_anon2 = Class.new(Onetime::Boot::Initializer) do
  def execute(_ctx); end
end
# Even though discover finds it, load_classes filters it out
discovered = Onetime::Boot::InitializerRegistry.discover { |k| k == @floating_anon2 }
@registry.send(:load_classes, discovered)
@registry.initializers.size
#=> 0

# ============================================================
# DSL-style initializer tests (simulates application/base.rb pattern)
# ============================================================

## DSL-style anonymous class with explicit name works with load
@registry = Onetime::Boot::InitializerRegistry.new
# Simulate the DSL pattern from application/base.rb
@dsl_init = Class.new(Onetime::Boot::Initializer) do
  @initializer_name = :'onetime.my_app.setup_feature'
  @provides = [:feature]
  @depends_on = []
  @optional = false

  class << self
    attr_reader :initializer_name, :provides, :depends_on, :optional
  end

  def execute(ctx)
    ctx[:feature_loaded] = true
  end
end
@registry.load([@dsl_init])
[@registry.initializers.size, @registry.initializers.first.name]
#=> [1, :"onetime.my_app.setup_feature"]

## DSL-style initializer executes correctly
@registry = Onetime::Boot::InitializerRegistry.new
@dsl_exec = Class.new(Onetime::Boot::Initializer) do
  @initializer_name = :'onetime.test.exec_check'

  class << self
    attr_reader :initializer_name
  end

  def execute(ctx)
    ctx[:executed] = true
  end
end
@registry.load([@dsl_exec])
results = @registry.run_all
[@registry.context[:executed], results[:successful].size]
#=> [true, 1]

## DSL-style with onetime prefix discovered by autodiscover filter
@registry = Onetime::Boot::InitializerRegistry.new
@dsl_discoverable = Class.new(Onetime::Boot::Initializer) do
  @initializer_name = :'onetime.apps.my_feature'

  class << self
    attr_reader :initializer_name
  end

  def execute(_ctx); end
end
# Simulate what autodiscover does - filter by initializer_name prefix
discovered = Onetime::Boot::InitializerRegistry.discover { |k|
  k.initializer_name&.to_s&.start_with?('onetime.')
}
discovered.include?(@dsl_discoverable)
#=> true

## DSL-style without onetime prefix NOT discovered by autodiscover filter
@registry = Onetime::Boot::InitializerRegistry.new
@dsl_not_discoverable = Class.new(Onetime::Boot::Initializer) do
  @initializer_name = :my_custom_feature  # No 'onetime.' prefix

  class << self
    attr_reader :initializer_name
  end

  def execute(_ctx); end
end
# autodiscover filter would reject this
discovered = Onetime::Boot::InitializerRegistry.discover { |k|
  k.initializer_name&.to_s&.start_with?('onetime.')
}
discovered.include?(@dsl_not_discoverable)
#=> false
