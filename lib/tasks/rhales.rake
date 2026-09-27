# lib/tasks/rhales.rake
#
# frozen_string_literal: true

# bundle exec rake rhales:schema:generate

require 'rhales'

begin
  spec         = Gem::Specification.find_by_name('rhales')
  rhales_tasks = "#{spec.gem_dir}/lib/tasks/rhales_schema.rake"
  load rhales_tasks
rescue Gem::LoadError
  warn 'Warning: Rhales gem not found'
rescue LoadError => ex
  warn "Warning: Rhales tasks not found: #{ex.message}"
end

# The gem's schema tasks read Rhales.configuration. Without the app's schema
# settings, `<schema src="bootstrap.ts">` in index.rue and admin.rue cannot be
# resolved and `rhales:schema:generate` reports "No schema sections found".
# Mirrors the schema settings in lib/onetime/initializers/configure_rhales.rb
# without booting the app.
#
# A prerequisite of those tasks ONLY, never run at load time: Rhales.configure
# freezes the configuration, and the app's initializer skips its own
# configuration when it finds it frozen. Configuring here at load would leave
# every rake task that boots the app with this partial configuration.
namespace :rhales do
  task :configure_schema_sources do
    # Rhales parses the whole stdout of `pnpm exec tsx` as JSON. pnpm 11
    # verifies dependencies before `exec` and prints "Already up to date" /
    # "Done in ..." to stdout ahead of the schema, so every schema fails to
    # parse. Skip that check for the subprocesses this task spawns.
    ENV['pnpm_config_verify_deps_before_run'] = 'false'

    next if Rhales.configuration.frozen?

    root = File.expand_path('../..', __dir__)
    Rhales.configure do |config|
      config.schema_search_paths   = [File.join(root, 'src', 'schemas', 'contracts')]
      config.schema_use_tsx_import = true
      config.schema_tsconfig_path  = File.join(root, 'tsconfig.json')
    end
  end
end

%w[rhales:schema:generate rhales:schema:stats].each do |name|
  Rake::Task[name].enhance(['rhales:configure_schema_sources']) if Rake::Task.task_defined?(name)
end
