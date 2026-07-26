# lib/tasks/locales.rake
#
# frozen_string_literal: true

# Locale sync tasks
#
# The primary workflow for locale management is now:
#   python locales/scripts/build/compile.py --all --merged
#
# This generates pre-merged JSON files in generated/locales/ which
# are consumed directly by the Ruby backend at boot time.
#
# The precompile/clean tasks have been removed as the cache system
# is no longer used.

namespace :locales do
  # Onetime::HOME comes from lib/onetime.rb, which the Rakefile does not load —
  # it only puts lib/ on the load path. Required inside each task body, not at
  # the top of this file, because the Rakefile loads every .rake at startup and
  # a top-level require would put that cost on every rake invocation. Same
  # pattern as dev.rake and init.rake.
  #
  # The entry point is the i18n CLI at locales/scripts/i18n; the standalone
  # build/compile.py these tasks used to call no longer exists. `compile` is
  # always merged now, so there is no --merged flag. Keep in lockstep with the
  # locales:generate / locales:sync scripts in package.json.
  def i18n_compile(*extra_args)
    require 'onetime'
    cli_path = File.join(Onetime::HOME, 'locales', 'scripts', 'i18n')
    system('python3', cli_path, 'content', 'compile', '--all', *extra_args) || exit(1)
  end

  desc 'Generate merged locale files from content JSON (calls Python i18n CLI)'
  task :sync do
    i18n_compile
  end

  desc 'Generate merged locale files (dry-run)'
  task :sync_dry_run do
    i18n_compile('--dry-run')
  end
end
