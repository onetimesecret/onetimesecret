# Rakefile
#
# frozen_string_literal: true

require 'bundler/setup'

# Load application rake tasks
Dir.glob('lib/tasks/**/*.rake').each { |r| load r }

# Load app-specific rake tasks (co-located with modular applications)
Dir.glob('apps/**/tasks/**/*.rake').each { |r| load r }
