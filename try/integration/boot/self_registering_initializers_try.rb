# try/integration/boot/self_registering_initializers_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require_relative '../../../lib/onetime/boot/initializer_registry'

# Uses InitializerRegistry.with_registry to ensure proper save/restore of
# the current registry. Each test case runs in isolation and automatically
# restores the previous registry (which may be valid) rather than nil.

## Self-registering pattern works
# App-defined initializers auto-load via current&.load() when defined
Onetime::Boot::InitializerRegistry.with_registry(Onetime::Boot::InitializerRegistry.new) do |registry|
  class TestAppForFile < Onetime::Application::Base
  end
  TestAppForFile.initializer(:file_init, provides: [:test]) { |_ctx| }
  registry.initializers.size
end
#=> 1

## Initializer name is correct
Onetime::Boot::InitializerRegistry.with_registry(Onetime::Boot::InitializerRegistry.new) do |registry|
  class TestApp2 < Onetime::Application::Base
  end
  TestApp2.initializer(:named_init) { |_ctx| }
  registry.initializers.first.name
end
#=> :named_init

## Provides capability works
Onetime::Boot::InitializerRegistry.with_registry(Onetime::Boot::InitializerRegistry.new) do |registry|
  class TestApp3 < Onetime::Application::Base
  end
  TestApp3.initializer(:provider, provides: [:cap]) { |_ctx| }
  registry.initializers.first.provides
end
#=> [:cap]

## Application class tracking works
Onetime::Boot::InitializerRegistry.with_registry(Onetime::Boot::InitializerRegistry.new) do |registry|
  class TestApp4 < Onetime::Application::Base
  end
  TestApp4.initializer(:tracked) { |_ctx| }
  registry.initializers.first.application_class
end
#=> TestApp4

## Multiple initializers from same app
Onetime::Boot::InitializerRegistry.with_registry(Onetime::Boot::InitializerRegistry.new) do |registry|
  class TestApp5 < Onetime::Application::Base
  end
  TestApp5.initializer(:first, provides: [:a]) { |_ctx| }
  TestApp5.initializer(:second, depends_on: [:a]) { |_ctx| }
  registry.initializers.size
end
#=> 2

## Dependency ordering with self-registered inits
Onetime::Boot::InitializerRegistry.with_registry(Onetime::Boot::InitializerRegistry.new) do |registry|
  class TestApp6 < Onetime::Application::Base
  end
  TestApp6.initializer(:base, provides: [:base]) { |_ctx| }
  TestApp6.initializer(:dependent, depends_on: [:base]) { |_ctx| }
  registry.execution_order.map(&:name)
end
#=> [:base, :dependent]

## Billing-style pattern with dependencies
Onetime::Boot::InitializerRegistry.with_registry(Onetime::Boot::InitializerRegistry.new) do |registry|
  class BillingStyle < Onetime::Application::Base
  end
  BillingStyle.initializer(:stripe, provides: [:stripe]) { |_ctx| }
  BillingStyle.initializer(:catalog, depends_on: [:database, :stripe], optional: true) { |_ctx| }
  registry.initializers.find { |i| i.name == :catalog }.dependencies.sort
end
#=> [:database, :stripe]

## Optional flag works in billing-style
Onetime::Boot::InitializerRegistry.with_registry(Onetime::Boot::InitializerRegistry.new) do |registry|
  class BillingStyleOptional < Onetime::Application::Base
  end
  BillingStyleOptional.initializer(:stripe, provides: [:stripe]) { |_ctx| }
  BillingStyleOptional.initializer(:catalog, depends_on: [:database, :stripe], optional: true) { |_ctx| }
  registry.initializers.find { |i| i.name == :catalog }.optional
end
#=> true

## Auth-style pattern with database dependency
Onetime::Boot::InitializerRegistry.with_registry(Onetime::Boot::InitializerRegistry.new) do |registry|
  class AuthStyle < Onetime::Application::Base
  end
  AuthStyle.initializer(:migrations, depends_on: [:database], provides: [:schema]) { |_ctx| }
  registry.initializers.first.dependencies
end
#=> [:database]

## ACME-style pattern
Onetime::Boot::InitializerRegistry.with_registry(Onetime::Boot::InitializerRegistry.new) do |registry|
  class AcmeStyle < Onetime::Application::Base
  end
  AcmeStyle.initializer(:preload, depends_on: [:database], provides: [:models]) { |_ctx| }
  registry.initializers.first.provides
end
#=> [:models]
