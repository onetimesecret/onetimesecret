# try/integration/boot/self_registering_initializers_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/boot/initializer_registry'

# Setup section
Onetime::Boot::InitializerRegistry.reset_all!

## Self-registering pattern works
class TestAppForFile < Onetime::Application::Base
end
TestAppForFile.initializer(:file_init, provides: [:test]) { |_ctx| }
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.initializers.size
#=> 1

## Initializer name is correct
Onetime::Boot::InitializerRegistry.reset_all!
class TestApp2 < Onetime::Application::Base
end
TestApp2.initializer(:named_init) { |_ctx| }
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.initializers.first.name
#=> :named_init

## Provides capability works
Onetime::Boot::InitializerRegistry.reset_all!
class TestApp3 < Onetime::Application::Base
end
TestApp3.initializer(:provider, provides: [:cap]) { |_ctx| }
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.initializers.first.provides
#=> [:cap]

## Application class tracking works
Onetime::Boot::InitializerRegistry.reset_all!
class TestApp4 < Onetime::Application::Base
end
TestApp4.initializer(:tracked) { |_ctx| }
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.initializers.first.application_class
#=> TestApp4

## Multiple initializers from same app
Onetime::Boot::InitializerRegistry.reset_all!
class TestApp5 < Onetime::Application::Base
end
TestApp5.initializer(:first, provides: [:a]) { |_ctx| }
TestApp5.initializer(:second, depends_on: [:a]) { |_ctx| }
Onetime::Boot::InitializerRegistry.load_all
Onetime::Boot::InitializerRegistry.initializers.size
#=> 2

## Dependency ordering with self-registered inits
Onetime::Boot::InitializerRegistry.reset_all!
class TestApp6 < Onetime::Application::Base
end
TestApp6.initializer(:base, provides: [:base]) { |_ctx| }
TestApp6.initializer(:dependent, depends_on: [:base]) { |_ctx| }
Onetime::Boot::InitializerRegistry.load_all
order = Onetime::Boot::InitializerRegistry.execution_order.map(&:name)
order
#=> [:base, :dependent]

## Billing-style pattern with dependencies
Onetime::Boot::InitializerRegistry.reset_all!
class BillingStyle < Onetime::Application::Base
end
BillingStyle.initializer(:stripe, provides: [:stripe]) { |_ctx| }
BillingStyle.initializer(:catalog, depends_on: [:database, :stripe], optional: true) { |_ctx| }
Onetime::Boot::InitializerRegistry.load_all
catalog = Onetime::Boot::InitializerRegistry.initializers.find { |i| i.name == :catalog }
catalog.dependencies.sort
#=> [:database, :stripe]

## Optional flag works in billing-style
Onetime::Boot::InitializerRegistry.initializers.find { |i| i.name == :catalog }.optional
#=> true

## Auth-style pattern with database dependency
Onetime::Boot::InitializerRegistry.reset_all!
class AuthStyle < Onetime::Application::Base
end
AuthStyle.initializer(:migrations, depends_on: [:database], provides: [:schema]) { |_ctx| }
Onetime::Boot::InitializerRegistry.load_all
migrations = Onetime::Boot::InitializerRegistry.initializers.first
migrations.dependencies
#=> [:database]

## ACME-style pattern
Onetime::Boot::InitializerRegistry.reset_all!
class AcmeStyle < Onetime::Application::Base
end
AcmeStyle.initializer(:preload, depends_on: [:database], provides: [:models]) { |_ctx| }
Onetime::Boot::InitializerRegistry.load_all
preload = Onetime::Boot::InitializerRegistry.initializers.first
preload.provides
#=> [:models]

# Teardown section
Onetime::Boot::InitializerRegistry.reset_all!
