# try/integration/boot/self_registering_initializers_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/boot/initializer_registry'

# Setup section
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry

## Self-registering pattern works
# App-defined initializers auto-load via current&.load() when defined
class TestAppForFile < Onetime::Application::Base
end
TestAppForFile.initializer(:file_init, provides: [:test]) { |_ctx| }
# No autodiscover needed - initializer was loaded on definition
@registry.initializers.size
#=> 1

## Initializer name is correct
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class TestApp2 < Onetime::Application::Base
end
TestApp2.initializer(:named_init) { |_ctx| }
@registry.initializers.first.name
#=> :named_init

## Provides capability works
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class TestApp3 < Onetime::Application::Base
end
TestApp3.initializer(:provider, provides: [:cap]) { |_ctx| }
@registry.initializers.first.provides
#=> [:cap]

## Application class tracking works
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class TestApp4 < Onetime::Application::Base
end
TestApp4.initializer(:tracked) { |_ctx| }
@registry.initializers.first.application_class
#=> TestApp4

## Multiple initializers from same app
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class TestApp5 < Onetime::Application::Base
end
TestApp5.initializer(:first, provides: [:a]) { |_ctx| }
TestApp5.initializer(:second, depends_on: [:a]) { |_ctx| }
@registry.initializers.size
#=> 2

## Dependency ordering with self-registered inits
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class TestApp6 < Onetime::Application::Base
end
TestApp6.initializer(:base, provides: [:base]) { |_ctx| }
TestApp6.initializer(:dependent, depends_on: [:base]) { |_ctx| }
order = @registry.execution_order.map(&:name)
order
#=> [:base, :dependent]

## Billing-style pattern with dependencies
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class BillingStyle < Onetime::Application::Base
end
BillingStyle.initializer(:stripe, provides: [:stripe]) { |_ctx| }
BillingStyle.initializer(:catalog, depends_on: [:database, :stripe], optional: true) { |_ctx| }
catalog = @registry.initializers.find { |i| i.name == :catalog }
catalog.dependencies.sort
#=> [:database, :stripe]

## Optional flag works in billing-style
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class BillingStyleOptional < Onetime::Application::Base
end
BillingStyleOptional.initializer(:stripe, provides: [:stripe]) { |_ctx| }
BillingStyleOptional.initializer(:catalog, depends_on: [:database, :stripe], optional: true) { |_ctx| }
@registry.initializers.find { |i| i.name == :catalog }.optional
#=> true

## Auth-style pattern with database dependency
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class AuthStyle < Onetime::Application::Base
end
AuthStyle.initializer(:migrations, depends_on: [:database], provides: [:schema]) { |_ctx| }
migrations = @registry.initializers.first
migrations.dependencies
#=> [:database]

## ACME-style pattern
@registry = Onetime::Boot::InitializerRegistry.new
Onetime::Boot::InitializerRegistry.current = @registry
class AcmeStyle < Onetime::Application::Base
end
AcmeStyle.initializer(:preload, depends_on: [:database], provides: [:models]) { |_ctx| }
preload = @registry.initializers.first
preload.provides
#=> [:models]

# Teardown - clear thread-local binding
Onetime::Boot::InitializerRegistry.current = nil
