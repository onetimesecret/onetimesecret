# lib/tasks/rhales.rake
#
# frozen_string_literal: true

# bundle exec rake rhales:schema:generate

require 'rhales'

# The gem's tasks read Rhales.configuration. Without the app's schema
# settings, `<schema src="bootstrap.ts">` in index.rue and admin.rue cannot be
# resolved and `rhales:schema:generate` reports "No schema sections found".
# Mirrors lib/onetime/initializers/configure_rhales.rb, without booting the app.
Rhales.configure do |config|
  root                         = File.expand_path('../..', __dir__)
  config.schema_search_paths   = [File.join(root, 'src', 'schemas', 'contracts')]
  config.schema_use_tsx_import = true
  config.schema_tsconfig_path  = File.join(root, 'tsconfig.json')
end

begin
  spec         = Gem::Specification.find_by_name('rhales')
  rhales_tasks = "#{spec.gem_dir}/lib/tasks/rhales_schema.rake"
  load rhales_tasks
rescue Gem::LoadError
  warn 'Warning: Rhales gem not found'
rescue LoadError => ex
  warn "Warning: Rhales tasks not found: #{ex.message}"
end
