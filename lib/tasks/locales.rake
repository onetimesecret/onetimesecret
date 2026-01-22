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
  desc 'Generate merged locale files from content JSON (calls Python sync script)'
  task :sync do
    script_path = File.join(Onetime::HOME, 'locales', 'scripts', 'build', 'compile.py')
    system('python3', script_path, '--all', '--merged') || exit(1)
  end

  desc 'Generate merged locale files (dry-run)'
  task :sync_dry_run do
    script_path = File.join(Onetime::HOME, 'locales', 'scripts', 'build', 'compile.py')
    system('python3', script_path, '--all', '--merged', '--dry-run') || exit(1)
  end
end
