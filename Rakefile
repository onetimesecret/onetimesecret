# Rakefile
#
# frozen_string_literal: true

require 'bundler/setup'

root = File.expand_path(__dir__)

$LOAD_PATH.unshift(File.join(root, 'lib'))

# Load application rake tasks
Dir.glob(File.join(root, 'lib/tasks/**/*.rake')).each(&method(:load))

# Load app-specific rake tasks (co-located with modular applications)
Dir.glob(File.join(root, 'apps/**/tasks/**/*.rake')).each(&method(:load))
